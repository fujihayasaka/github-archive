# typed: strict
# frozen_string_literal: true

module Copilot
  class ModelsRegistryCache < ApplicationRecord::Copilot

    include GitHub::Memoizer

    self.table_name = "model_registry_cache"

    serialize :plans, type: Array, default: []

    validates :model_key, presence: true, uniqueness: true
    validates :name, presence: true

    sig { params(copilot_entity: T.any(Copilot::Organization, Copilot::User)).returns(T.nilable(String)) }
    def self.determine_plan(copilot_entity)
      return "enterprise" if copilot_entity.copilot_plan_enterprise?
      return "business" if copilot_entity.copilot_plan_business?

      case copilot_entity
      when Copilot::User
        if copilot_entity.copilot_plan_individual?
          return "pro_plus" if copilot_entity.has_pro_plus_access?
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
        plans << "enterprise" if copilot_user.copilot_organizations.any?(&:copilot_plan_enterprise?)

        # Add business models if user has any business orgs
        plans << "business" if copilot_user.copilot_organizations.any?(&:copilot_plan_business?)

        return [] if plans.empty?

        # Get models for all plans and deduplicate
        models = plans.flat_map { |plan| filtered_models(copilot_user, plan) }
        return models.uniq
      end

      # For individual users, use the single plan approach
      plan = determine_plan(copilot_user)
      return [] unless plan.present?
      filtered_models(copilot_user, plan)
    end

    sig { params(copilot_business: Copilot::Business).returns(T::Array[ModelsRegistryCache]) }
    def self.for_enterprise(copilot_business)
      # Enterprises don't have a plan, they assign plans to their organizations
      # and so should get all models for both copilot_business and copilot_enterprise
      business_models = filtered_models(copilot_business, "business")
      enterprise_models = filtered_models(copilot_business, "enterprise")

      (business_models + enterprise_models).uniq
    end

    sig { params(organization: Copilot::Organization).returns(T::Array[ModelsRegistryCache]) }
    def self.for_organization(organization)
      return [] unless organization.has_copilot_for_business? || organization.on_free_copilot_business_trial? || organization.on_free_copilot_enterprise_trial?
      plan = determine_plan(organization)
      return [] unless plan.present?
      filtered_models(organization, plan)
    end

    sig { params(copilot_entity: T.any(Copilot::Business, Copilot::Organization, Copilot::User), plan: String).returns(T::Array[ModelsRegistryCache]) }
    def self.filtered_models(copilot_entity, plan)
      return [] unless plan.present?

      show_internal_models = copilot_entity.feature_flag_enabled?(:copilot_registry_internal_models_testing, default: false)

      all.select do |model|
        feature_flag = model.feature_flag || ""
        next false unless model.plans.include?(plan)
        next false unless feature_flag.empty? || copilot_entity.feature_flag_enabled?(feature_flag.to_sym, default: false)
        if model.internal
          next false unless show_internal_models
        end
        # For individual users (CFI only, not CFB/CFE), only show models with inline_approval_enabled
        if T.unsafe(copilot_entity).is_a?(Copilot::User)
          copilot_user = T.cast(copilot_entity, Copilot::User)
          unless copilot_user.has_cfb_access? || copilot_user.has_cfe_access?
            next false unless model.inline_approval_enabled
          end
        end
        true
      end
    end

    sig { returns(T::Array[ModelsRegistryCache]) }
    def self.pull_models
      model_client = CopilotModelRegistry::Twirp::ModelClient.new
      models = model_client.get_models
      models = models.map do |model_hash|
        model_hash = model_hash.transform_keys { |key| key.to_s == "key" ? "model_key".to_sym : key }

        ModelsRegistryCache.new(
          model_key: model_hash[:model_key].to_s,
          name: model_hash[:name].to_s,
          description: model_hash[:description].to_s,
          # `plans` is a Google::Protobuf::RepeatedField, so we must convert the values to strings before saving
          plans: Array(model_hash[:plans]).map { |plan| plan.to_s },
          feature_flag: model_hash[:feature_flag].to_s,
          internal: !!model_hash[:internal],
          preview: !!model_hash[:preview],
          documentation_link: model_hash[:documentation_link].to_s,
          documentation_link_text: model_hash[:documentation_link_text].to_s,
          inline_approval_enabled: !!model_hash[:inline_approval_enabled],
        )
      end
      models
    end

    sig { void }
    def self.save_models
      models = pull_models
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
            },
          )
        end

        # Delete models that are no longer in the pulled data
        ModelsRegistryCache.where.not(model_key: pulled_model_keys).delete_all
      end
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
