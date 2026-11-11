# typed: strict
# frozen_string_literal: true

module Copilot
  class ModelsRegistryCache < ApplicationRecord::Copilot

    include GitHub::Memoizer

    self.table_name = "model_registry_cache"

    serialize :plans, type: Array, default: []

    validates :model_key, presence: true, uniqueness: true
    validates :name, presence: true

    # Cache key for model registry
    CACHE_KEY = "copilot:models_registry:all:v2"

    # Cache all models since the table is small and rarely changes
    # We cache the attributes as JSON, not AR objects, to avoid serialization issues
    sig { returns(T::Array[ModelsRegistryCache]) }
    def self.all_cached
      # 1. Get the Safe Allow-list (only columns this code version knows)
      known_keys = column_names.map(&:to_s)

      cached_attrs = GitHub.cache.fetch(
        CACHE_KEY,
        ttl: 5.minutes,
        stats_key: "copilot.models_registry.all.cache",
        raw: true
      ) do
        # Cache writes: filter for consistency/forward-compat; reads still enforce filtering strictly
        all.map { |r| r.attributes.slice(*known_keys) }.to_json
      end

      # 2. Cache Reads: FILTER IS MANDATORY HERE
      JSON.parse(cached_attrs).map do |attrs|
        # This prevents the UnknownAttributeError crash
        ModelsRegistryCache.new(attrs.slice(*known_keys))
      end

    rescue JSON::ParserError
      # 3. DB Fallback: standard AR loading is already safe
      all.to_a
    end

    sig { params(copilot_entity: T.any(Copilot::Organization, Copilot::User)).returns(T.nilable(String)) }
    def self.determine_plan(copilot_entity)
      return "enterprise" if copilot_entity.copilot_plan_enterprise?
      return "business" if copilot_entity.copilot_plan_business?

      case copilot_entity
      when Copilot::User
        if copilot_entity.copilot_plan_individual?
          return "pro_plus" if copilot_entity.has_pro_plus_access?
          return "edu" if copilot_entity.edu_signup_enabled? && copilot_entity.has_educational_access?
          return "pro" if copilot_entity.has_pro_access? || copilot_entity.has_free_access?
          return "free" if copilot_entity.has_limited_access?
        end
      end

      nil
    end

    sig { params(copilot_user: Copilot::User).returns(T::Array[ModelsRegistryCache]) }
    def self.for_user(copilot_user)
      return [] unless copilot_user.has_copilot_access? || copilot_user.has_cfe_access? || copilot_user.has_cfb_access?

      # For users with business/enterprise access, get models for all their plans
      if copilot_user.has_cfb_access? || copilot_user.has_cfe_access?
        plans = []

        # Add enterprise models if user has any enterprise orgs
        plans << "enterprise" if copilot_user.copilot_organizations.any?(&:copilot_plan_enterprise?) || copilot_user.copilot_businesses.any?(&:copilot_plan_enterprise?)

        # Add business models if user has any business orgs
        plans << "business" if copilot_user.copilot_organizations.any?(&:copilot_plan_business?) || copilot_user.copilot_businesses.any?(&:copilot_plan_business?)


        return [] if plans.empty?

        # Get models for all plans and deduplicate
        models = plans.flat_map { |plan| filtered_models(copilot_user, plan) }
        return models.uniq.sort_by(&:name)
      end

      # For individual users, use the single plan approach
      plan = determine_plan(copilot_user)
      return [] unless plan.present?
      filtered_models(copilot_user, plan)
    end

    sig { params(copilot_entity: T.any(Copilot::Business, Copilot::Organization, Copilot::User)).returns(T::Array[ModelsRegistryCache]) }
    def self.for_entity(copilot_entity)
      case copilot_entity
      when Copilot::Business
        for_enterprise(copilot_entity)
      when Copilot::Organization
        for_organization(copilot_entity)
      when Copilot::User
        for_user(copilot_entity)
      else
        T.absurd(copilot_entity)
      end
    end

    sig { params(copilot_business: Copilot::Business).returns(T::Array[ModelsRegistryCache]) }
    def self.for_enterprise(copilot_business)
      # Enterprises don't have a plan, they assign plans to their organizations
      # and so should get all models for both copilot_business and copilot_enterprise
      business_models = filtered_models(copilot_business, "business")
      enterprise_models = filtered_models(copilot_business, "enterprise")

      (business_models + enterprise_models).uniq.sort_by(&:name)
    end

    sig { params(organization: Copilot::Organization).returns(T::Array[ModelsRegistryCache]) }
    def self.for_organization(organization)
      if organization.has_copilot_for_business? || organization.on_free_copilot_business_trial? || organization.on_free_copilot_enterprise_trial?
        plan = determine_plan(organization)
        return [] unless plan.present?

        return filtered_models(organization, plan)
      end
      # if the org doesn't have a copilot plan but has direct org billing enabled, treat them as if they have copilot_for_business plan
      return filtered_models(organization, "business") if organization.has_copilot_direct_org_billing_enabled?

      []
    end

    sig { params(copilot_entity: T.any(Copilot::Business, Copilot::Organization, Copilot::User), plan: String).returns(T::Array[ModelsRegistryCache]) }
    def self.filtered_models(copilot_entity, plan)
      return [] unless plan.present?

      show_internal_models = copilot_entity.feature_flag_enabled?(:copilot_registry_internal_models_testing, default: false)
      all_models_enabled_for_ci = copilot_entity.feature_flag_enabled?(:all_models_enabled_for_ci, default: false)

      models = all_cached.select do |model|
        model_enabled = feature_flag_enabled?(model.feature_flag, copilot_entity)
        next false unless model.plans.include?(plan) && model_enabled
        next false if model.internal && !show_internal_models

        # For Users and Orgs on 'pro' or 'business' plans, only show models with policy_pro_feature_flag enabled
        if %w[pro business].include?(plan) && !copilot_entity.is_a?(Copilot::Business)
          next false unless feature_flag_enabled?(model.policy_pro_feature_flag, copilot_entity)
        end

        # For individual users (CFI only, not CFB/CFE), only show models with inline_approval_enabled
        # unless all_models_enabled_for_ci is on, which force-enables all models for individuals
        unless %w[business enterprise].include?(plan)
          next false unless model.inline_approval_enabled || all_models_enabled_for_ci
        end

        true
      end

      models.sort_by(&:name)
    end

    # Helper method to check if a feature flag is enabled for a given copilot entity
    # as some entities require a symbol.
    # Empty flag means always enabled.
    sig { params(flag: T.any(String, Symbol, NilClass), copilot_entity: T.any(Copilot::Business, Copilot::Organization, Copilot::User)).returns(T::Boolean) }
    def self.feature_flag_enabled?(flag, copilot_entity)
      return true if flag.to_s.empty?
      copilot_entity.feature_flag_enabled?(flag.to_s.to_sym, default: false)
    end

    sig { returns(T::Array[ModelsRegistryCache]) }
    def self.pull_models
      model_client = CopilotModelRegistry::Twirp::ModelClient.new
      models = model_client.get_models
      models = models.map do |model_hash|
        model_hash = model_hash.transform_keys { |key| key.to_s == "key" ? "model_key".to_sym : key }

        ModelsRegistryCache.new(
          model_key: model_hash[:model_key].to_s,
          name: prefixed_model_name(model_hash[:name], model_hash[:vendor]),
          description: model_hash[:description].to_s,
          # `plans` is a Google::Protobuf::RepeatedField, so we must convert the values to strings before saving
          plans: Array(model_hash[:plans]).map { |plan| plan.to_s },
          feature_flag: model_hash[:feature_flag].to_s,
          internal: !!model_hash[:internal],
          preview: !!model_hash[:preview],
          documentation_link: model_hash[:documentation_link].to_s,
          documentation_link_text: model_hash[:documentation_link_text].to_s,
          inline_approval_enabled: !!model_hash[:inline_approval_enabled],
          policy_pro_feature_flag: model_hash[:policy_pro_feature_flag].to_s,
          policy_ga_feature_flag: model_hash[:policy_ga_feature_flag].to_s,
          policy_rollout_complete_feature_flag: model_hash[:policy_rollout_complete_feature_flag].to_s,
          vendor: model_hash[:vendor].to_s,
        )
      end
      models
    end

    sig { params(name: T.nilable(String), vendor: T.nilable(String)).returns(String) }
    def self.prefixed_model_name(name, vendor)
      name_string = name.to_s.strip
      vendor_string = vendor.to_s.strip

      return name_string if vendor_string.blank?

      # If the name is already prefixed (e.g. "OpenAI GPT-2"), don't double prefix
      return name_string if name_string.include?(vendor_string)

      "#{vendor_string} #{name_string}"
    end

    sig { void }
    def self.save_models
      # Get current models before update to detect changes
      cached_models = all_cached
      models = pull_models

      # Check if models have actually changed
      models_have_changed = models_changed?(cached_models, models)

      with_write do
        pulled_model_keys = models.map(&:model_key)

        models.each do |model|
          ModelsRegistryCache.upsert(
            {
              model_key: model.model_key,
              name: model.name,
              description: model.description,
              plans: model.plans,
              feature_flag: model.feature_flag,
              internal: model.internal,
              preview: model.preview,
              documentation_link: model.documentation_link,
              documentation_link_text: model.documentation_link_text,
              inline_approval_enabled: model.inline_approval_enabled,
              policy_pro_feature_flag: model.policy_pro_feature_flag,
              policy_ga_feature_flag: model.policy_ga_feature_flag,
              policy_rollout_complete_feature_flag: model.policy_rollout_complete_feature_flag,
              vendor: model.vendor,
            },
          )
        end

        # Delete models that are no longer in the pulled data
        ModelsRegistryCache.where.not(model_key: pulled_model_keys).delete_all
      end

      # Force cache expiration if models changed - delete from all caches for multi-site compatibility
      if models_have_changed
        [GitHub.cache, *GitHub.regional_caches.values].each do |cache|
          cache.delete(CACHE_KEY)
        end
        GitHub.logger.info("Models registry cache expired due to changes", {
          "code.namespace": "Copilot::ModelsRegistryCache",
          "code.function": "save_models",
        })
      end
    rescue => e
      # Log error and re-raise to allow background job retry on transient failures
      GitHub.logger.error("Error saving models to registry cache", {
        "code.namespace": "Copilot::ModelsRegistryCache",
        "code.function": "save_models",
        "error": e.message,
        "error.class": e.class.name,
      })
      raise # Re-raise so job can retry
    end

    # Check if there is a diff between cached models and pulled models for a field
    sig { params(cached: T::Array[ModelsRegistryCache], pulled: T::Array[ModelsRegistryCache]).returns(T::Boolean) }
    def self.models_changed?(cached, pulled)
      cached_keys = cached.map(&:model_key).sort
      pulled_keys = pulled.map(&:model_key).sort
      return true if cached_keys != pulled_keys # Different models
      cached.each do |cached_model|
        pulled_model = pulled.find { |m| m.model_key == cached_model.model_key }
        return true if pulled_model.nil?
        return true if cached_model.name != pulled_model.name
        return true if cached_model.description != pulled_model.description
        return true if cached_model.plans.sort != pulled_model.plans.sort
        return true if cached_model.feature_flag != pulled_model.feature_flag
        return true if cached_model.internal != pulled_model.internal
        return true if cached_model.preview != pulled_model.preview
        return true if cached_model.documentation_link != pulled_model.documentation_link
        return true if cached_model.documentation_link_text != pulled_model.documentation_link_text
        return true if cached_model.inline_approval_enabled != pulled_model.inline_approval_enabled
        return true if cached_model.policy_pro_feature_flag != pulled_model.policy_pro_feature_flag
        return true if cached_model.policy_ga_feature_flag != pulled_model.policy_ga_feature_flag
        return true if cached_model.policy_rollout_complete_feature_flag != pulled_model.policy_rollout_complete_feature_flag
        return true if cached_model.vendor != pulled_model.vendor
      end
      false
    end

    sig { void }
    def self.clear_models
      with_write do
        ModelsRegistryCache.delete_all
      end
    end
  end
end
