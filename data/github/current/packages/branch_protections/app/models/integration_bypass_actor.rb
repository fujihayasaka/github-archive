# typed: true
# frozen_string_literal: true

class IntegrationBypassActor < RepositoryRulesetBypassActor
  extend RuleEngine::Timing

  def self.display_type
    "Integration"
  end

  def self.display_name
    "Integration"
  end

  sig { returns(T.nilable(Integration)) }
  def integration
    actor
  end

  sig { returns(T.nilable(String)) }
  def actor_owner_name
    integration&.owner&.display_login
  end

  sig { returns(T.nilable(String)) }
  def actor_preferred_avatar_url
    T.let(integration&.preferred_avatar_url, T.nilable(String))
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      query: T.nilable(String),
      limit: Integer,
      resources: T::Array[String],
      min_action: Symbol,
      enterprise_only: T::Boolean,
    )
    .returns(T::Array[IntegrationBypassActor])
  end
  def self.suggest_bypassers(source, query = "", limit: 100, resources: Repository::Resources.subject_types, min_action: :write, enterprise_only: false)
    return self.new_suggest_bypassers(source, query, limit:, resources:, min_action:, enterprise_only:) if source.feature_enabled_for_source?(:rulesets_new_suggest_bypassers)

    bypass_actors = []

    trace_time("suggestions.integrations", tags: ["type:installed_with_#{min_action}_access", "source:#{source.class.name}"]) do
      integrations = T.let([], T::Array[Integration])

      installations = case source
      when Repository
        business = source.organization&.business
        if business.present?
          enterprise_installation_ids = []
          installation_ids_with_permissions = IntegrationInstallation.ids_with_resources_on(
          subject_class: source.class,
          subject_id: source.id,
          subject_owner_id: source.organization_id,
          resources: resources,
          min_action: min_action
        )

          enterprise_installation_ids = business.integration_installations.pluck(:id)

          all_installation_ids = installation_ids_with_permissions + enterprise_installation_ids
          IntegrationInstallation.where(id: all_installation_ids)
        else
          IntegrationInstallation.with_resources_on(
            subject: source,
            resources: resources,
            min_action: min_action
          )
        end
      when User
        installation_ids_on_all_repos = []
        installation_ids_on_individual_repos = []

        all_installation_ids = IntegrationInstallation.where(target: source).pluck(:id)

        # Get all installations that are granted access to all repositories
        installation_ids_on_all_repos =
          Permission.from("permissions FORCE INDEX(index_permissions_on_actor_subject_and_action)")
            .where(
              actor_type: IntegrationInstallation,
              actor_id: all_installation_ids,
              subject_id: source.id,
              # User/repositories/checks
              subject_type: Repository::Resources.all_type_prefixed_subject_types(resources),
            )
            .where("action >= ?", Permission.actions[min_action])
            .distinct
            .pluck(:actor_id)

        run_query = true
        if source.dont_check_repos_integrations_limit?
          num_repos = source.repositories.count
          limit = 100000
          limit = (limit * (FeatureFlag.vexi.percentage_of_calls_value_or_raise(:dont_check_repos_integrations_limit_value) / 100)).to_i # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
          run_query = num_repos < limit
        end

        if run_query
          # Get all installations that are granted access to repositories individually
          installation_ids_on_individual_repos = Permission.from("permissions FORCE INDEX(index_permissions_on_actor_subject_and_action)")
            .where(
              actor_type: IntegrationInstallation,
              actor_id: all_installation_ids,
              subject_type: Repository::Resources.individual_type_prefixed_subject_types(resources),
            ).where("action >= ?", Permission.actions[min_action])
            .distinct
            .pluck(:actor_id)
        end

        installation_ids_on_enterprise_apps = []
        business = source.business
        if business.present?
          installation_ids_on_enterprise_apps = business.integration_installations.pluck(:id)
        end

        installation_ids = installation_ids_on_all_repos + installation_ids_on_individual_repos + installation_ids_on_enterprise_apps

        IntegrationInstallation.where(id: installation_ids)
      when Business
        org_ids = source.organization_ids

        installation_ids = []
        installation_ids.concat(source.integration_installations.pluck(:id))
        unless enterprise_only
          installation_ids.concat(IntegrationInstallation.where(target_type: "User", target_id: org_ids).pluck(:id))
        end

        IntegrationInstallation.where(id: installation_ids)
      end

      candidates = (installations || IntegrationInstallation.none).user_installable

      GitHub::PrefillAssociations.prefill_associations(candidates, [:integration])

      candidates = candidates.filter do |installation|
        installation.integration.name.downcase.include?(query)
      end unless query.blank?

      unless enterprise_only
        if self.dependabot_can_bypass(source) &&
          GitHub.dependabot_github_app.present? &&
          (query.blank? || GitHub.dependabot_github_app_name.downcase.include?(query))
          integrations << GitHub.dependabot_github_app
        end

        if BypassCheckHelper.merge_queue_can_bypass(source) && (query.blank? || GitHub.merge_queue_github_app_name.downcase.include?(query))
          integrations << GitHub.merge_queue_bot.integration
        end

        if self.copilot_coding_agent_can_bypass?(source) && (query.blank? || "copilot coding agent".include?(query))
          copilot_coding_agent = Apps::Privileged.integration(:copilot_swe_agent)
          integrations << copilot_coding_agent unless copilot_coding_agent.nil?
        end

        if self.copilot_code_review_can_bypass?(source) && (query.blank? || "copilot code review".include?(query))
          copilot_code_review = Apps::Privileged.integration(:copilot_pull_request_reviewer)
          integrations << copilot_code_review unless copilot_code_review.nil?
        end
      end

      candidates.each do |installation|
        integrations << installation.integration unless installation.integration.nil?
      end

      integrations = integrations
      .flatten
      .uniq { |integration| integration.id }
      .sort_by { |integration| integration.name }

      integrations.each do |integration|
        bypass_actors << IntegrationBypassActor.new(actor: integration)
      end
    end
    bypass_actors
  end

  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      query: T.nilable(String),
      limit: Integer,
      resources: T::Array[String],
      min_action: Symbol,
      enterprise_only: T::Boolean,
    )
    .returns(T::Array[IntegrationBypassActor])
  end
  def self.new_suggest_bypassers(source, query = "", limit: 100, resources: Repository::Resources.subject_types, min_action: :write, enterprise_only: false)
    bypass_actors = []

    trace_time("suggestions.integrations", tags: ["type:installed_with_#{min_action}_access", "source:#{source.class.name}"]) do
      integrations = T.let([], T::Array[Integration])

      candidates = case source
      when Repository
        repo_installations = IntegrationInstallation
          .with_resources_on(
            subject: source,
            resources: resources,
            min_action: min_action
          ).user_installable.to_a

        business = source.organization&.business
        if business.present?
          enterprise_installations = business.integration_installations.user_installable.to_a
          repo_installations.concat(enterprise_installations)
        end

        repo_installations
      when User
        installation_ids_on_all_repos = []
        installation_ids_on_individual_repos = []

        installations_by_id = IntegrationInstallation.where(target: source).user_installable.index_by(&:id)

        # Get all installations that are granted access to all repositories
        installation_ids_on_all_repos =
          Permission.from("permissions FORCE INDEX(index_permissions_on_actor_subject_and_action)")
            .where(
              actor_type: IntegrationInstallation,
              actor_id: installations_by_id.keys,
              subject_id: source.id,
              # User/repositories/checks
              subject_type: Repository::Resources.all_type_prefixed_subject_types(resources),
            )
            .where("action >= ?", Permission.actions[min_action])
            .distinct
            .pluck(:actor_id)

        run_query = true
        if source.dont_check_repos_integrations_limit?
          num_repos = source.repositories.count
          limit = 100000
          limit = (limit * (FeatureFlag.vexi.percentage_of_calls_value_or_raise(:dont_check_repos_integrations_limit_value) / 100)).to_i # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
          run_query = num_repos < limit
        end

        if run_query
          # Get all installations that are granted access to repositories individually
          installation_ids_on_individual_repos = Permission.from("permissions FORCE INDEX(index_permissions_on_actor_subject_and_action)")
            .where(
              actor_type: IntegrationInstallation,
              actor_id: installations_by_id.keys,
              subject_type: Repository::Resources.individual_type_prefixed_subject_types(resources),
            ).where("action >= ?", Permission.actions[min_action])
            .distinct
            .pluck(:actor_id)
        end

        all_installation_ids = installation_ids_on_all_repos + installation_ids_on_individual_repos
        org_installations = installations_by_id.values_at(*all_installation_ids).compact

        business = source.business
        if business.present?
          business_installations = business.integration_installations.user_installable.to_a
          org_installations.concat(business_installations)
        end

        org_installations
      when Business
        org_ids = source.organization_ids

        business_installations = source.integration_installations.user_installable.to_a
        business_installations.concat(IntegrationInstallation.where(target_type: "User", target_id: org_ids).user_installable.to_a) unless enterprise_only
        business_installations
      end

      GitHub::PrefillAssociations.prefill_associations(candidates, [:integration])

      candidates = candidates.filter do |installation|
        installation.integration.name.downcase.include?(query)
      end unless query.blank?

      unless enterprise_only
        if self.dependabot_can_bypass(source) &&
          GitHub.dependabot_github_app.present? &&
          (query.blank? || GitHub.dependabot_github_app_name.downcase.include?(query))
          integrations << GitHub.dependabot_github_app
        end

        if BypassCheckHelper.merge_queue_can_bypass(source) && (query.blank? || GitHub.merge_queue_github_app_name.downcase.include?(query))
          integrations << GitHub.merge_queue_bot.integration
        end

        if self.copilot_coding_agent_can_bypass?(source) && (query.blank? || "copilot coding agent".include?(query))
          copilot_coding_agent = Apps::Privileged.integration(:copilot_swe_agent)
          integrations << copilot_coding_agent unless copilot_coding_agent.nil?
        end

        if self.copilot_code_review_can_bypass?(source) && (query.blank? || "copilot code review".include?(query))
          copilot_code_review = Apps::Privileged.integration(:copilot_pull_request_reviewer)
          integrations << copilot_code_review unless copilot_code_review.nil?
        end
      end

      candidates.each do |installation|
        integrations << installation.integration unless installation.integration.nil?
      end

      integrations = integrations
      .flatten
      .uniq { |integration| integration.id }
      .sort_by { |integration| integration.name }

      integrations.each do |integration|
        bypass_actors << IntegrationBypassActor.new(actor: integration)
      end
    end
    bypass_actors
  end

  sig do
    params(
      bypassers: T::Array[IntegrationBypassActor],
      actor: RuleEngine::Types::Actor,
      targetable: Targeting::Targetable
    ).returns(T::Array[Symbol])
  end
  def self.allowed_bypass_modes(bypassers, actor, targetable)
    allowed_modes = []

    # Check bypass allowances for this integration
    if actor.is_a?(Bot) && actor.integration
      actor_integration_id = T.must(actor.integration).id

      # Check for bypass granted to this integration
      bypasser = bypassers.find { |ba| ba.actor_id == actor_integration_id }
      if bypasser
        allowed_modes << bypasser.bypass_mode
      end
    end
    allowed_modes
  end

  sig do
    params(source: RuleEngine::Types::RuleSource).
    returns(T::Boolean)
  end
  private_class_method def self.dependabot_can_bypass(source)
    source.is_a?(Business) || source.dependabot_installed?
  end

  sig do
    params(source: RuleEngine::Types::RuleSource).
    returns(T::Boolean)
  end
  private_class_method def self.copilot_coding_agent_can_bypass?(source)
    return false unless Apps::Privileged.integration(:copilot_swe_agent).present?

    true
  end

  sig do
    params(source: RuleEngine::Types::RuleSource).
    returns(T::Boolean)
  end
  private_class_method def self.copilot_code_review_can_bypass?(source)
    return false unless Apps::Privileged.integration(:copilot_pull_request_reviewer).present?

    true
  end
end
