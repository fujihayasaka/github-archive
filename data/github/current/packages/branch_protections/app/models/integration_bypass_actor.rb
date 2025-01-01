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
    T.let(actor, T.nilable(Integration))
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
    )
    .returns(T::Array[IntegrationBypassActor])
  end
  def self.suggest_bypassers(source, query = "", limit: 100, resources: Repository::Resources.subject_types, min_action: :write)
    bypass_actors = []

    trace_time("suggestions.integrations", tags: ["type:installed_with_#{min_action}_access", "source:#{source.class.name}"]) do
      integrations = T.let([], T::Array[Integration])

      installations = case source
      when Repository
        IntegrationInstallation.with_resources_on(
          subject: source,
          resources: resources,
          min_action: min_action,
        )
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

        installation_ids = installation_ids_on_all_repos + installation_ids_on_individual_repos

        IntegrationInstallation.where(id: installation_ids)
      when Business
        if source.enterprise_rulesets_enterprise_apps_enabled?
          org_ids = source.organization_ids

          installation_ids = []
          installation_ids.concat(source.integration_installations.pluck(:id))
          installation_ids.concat(IntegrationInstallation.where(target_type: "User", target_id: org_ids).pluck(:id))

          IntegrationInstallation.where(id: installation_ids)
        else
          return []
        end
      end

      candidates = (installations || IntegrationInstallation.none).user_installable

      GitHub::PrefillAssociations.prefill_associations(candidates, [:integration])

      candidates = candidates.filter do |installation|
        installation.integration.name.downcase.include?(query)
      end unless query.blank?

      if self.dependabot_can_bypass(source) &&
        GitHub.dependabot_github_app.present? &&
        (query.blank? || GitHub.dependabot_github_app_name.downcase.include?(query))
        integrations << GitHub.dependabot_github_app
      end

      if self.merge_queue_can_bypass(source) && (query.blank? || GitHub.merge_queue_github_app_name.downcase.include?(query))
        integrations << GitHub.merge_queue_bot.integration
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
      targetable: RuleEngine::Conditions::Targetable
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
  private_class_method def self.merge_queue_can_bypass(source)
    # Merge queue is globally enabled for this instance
    return false unless source.merge_queue_bot_bypass_enabled?
    return false unless GitHub.merge_queues_enabled?
    return false unless GitHub.merge_queue_bot.present?

    GitHub.enterprise? || \
      source.plan_supports?(:merge_queue) || \
      (source.is_a?(Organization) && source.plan_supports?(:merge_queue, visibility: :public)) || \
      (source.is_a?(Business) && source.plan.supports?(:merge_queue, org: true, visibility: :public)) || \
      source.feature_flag_enabled?(:merge_queue, memoize: false, default: false)
  end
end
