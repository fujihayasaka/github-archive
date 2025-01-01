# typed: strict
# frozen_string_literal: true

module RulesEngine
  module Suggestions
    extend T::Sig
    extend RuleEngine::Timing

    TEAMS_BYPASS_LIMIT = 10
    MAX_SUGGESTIONS = 100

    # TODO: Remove support for ruleset_id as it is no longer necessaary
    # Public: Fetch integrations with write access for the specified source,
    # as well as integrations from the last week of check runs
    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        ruleset_id: T.nilable(Integer),
        query: T.nilable(String),
      )
      .returns(T::Array[{ id: Integer, name: String, preferred_avatar_url: String }])
    end
    def self.status_check_integrations_for(
      source,
      ruleset_id: nil,
      query: nil
    )
      ruleset = RepositoryRuleset.load_for(source: source, include_parents: true)
        .find { |ruleset| ruleset.id == ruleset_id.to_i } unless ruleset_id.blank?

      integrations = integrations_for(
        ruleset&.source || source,
        resources: %w[statuses checks],
        query: query
      )

      if source.is_a?(::Repository)
        trace_time("suggestions.status_check_integrations.duration", tags: ["type:check_runs", "source:#{source.class.name}"]) do
          check_runs = CheckRun.recent_check_names_and_integrations(repo: source, start: 1.week.ago, limit: MAX_SUGGESTIONS)

          check_runs.values.flat_map do |check_run_integrations|
            check_run_integrations.each do |integration|
              owner = integration.owner.display_login

              integrations << {
                id: T.must(integration.id),
                name: integration.name,
                preferred_avatar_url: integration.preferred_avatar_url,
                owner:,
              }
            end
          end
        end
      end

      unless ruleset.nil?
        trace_time("suggestions.integrations.duration", tags: ["type:ruleset", "source:#{source.class.name}"]) do
          required_status_check_rule = ruleset.rule_configurations.find { |rule| rule.rule_type == "required_status_checks" }

          required_status_checks = required_status_check_rule&.param("required_status_checks")
          integration_ids = required_status_checks&.filter_map { |required_status_check| required_status_check["integration_id"] }

          unless integration_ids.blank?
            Integration.where(id: integration_ids.uniq).each do |integration|
              owner = integration.owner.display_login

              integrations << {
                id: integration.id,
                name: integration.name,
                preferred_avatar_url: integration.preferred_avatar_url,
                owner:,
              }
            end
          end
        end
      end

      integrations
        .flatten
        .uniq { |integration| integration[:id] }
        .sort_by { |integration| integration[:name] }
    end

    # Public: Fetch recent status checks for the specified source
    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        query: String,
        limit: Integer
      )
      .returns(T::Array[{ context: String, latest_integration_id: T.nilable(Integer) }])
    end
    def self.recent_status_checks_for(source, query, limit: 100)
      trace_time("suggestions.recent_status_checks_for", tags: ["source:#{source.class.name}"]) do
        return [] unless source.is_a?(::Repository)

        start = 1.week.ago

        # Neither query supports filtering by context, so we overfetch to ensure we have enough
        # potential matches to return the requested number of results.
        status_checks = trace_time("suggestions.recent_status_checks.load", tags: ["source:statuses"]) do
          Statuses::Service.recent_status_contexts_and_integrations(repo_id: source.id, start:, limit: MAX_SUGGESTIONS)
        end

        check_runs = trace_time("suggestions.recent_status_checks.load", tags: ["source:check_runs"]) do
          CheckRun.recent_check_names_and_integrations(repo: source, start:, limit: MAX_SUGGESTIONS)
        end

        recent_status_checks = status_checks.merge(check_runs) { |_, set_a, set_b| set_a | set_b }

        recent_status_checks
          .select { |context| context.downcase.include?(query.downcase) }
          .map do |context, integrations|
            {
              context: context,
              latest_integration_id: integrations.first&.id,
            }
          end
          .sort_by { |status_check| status_check[:context] }
          .take(limit)
      end
    end

    # Public: Fetch deployment environments for the specified source
    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        query: String
      )
      .returns(T::Array[String])
    end
    def self.deployment_environments_for(source, query)
      return [] unless source.is_a?(::Repository)

      source.environments.where("name LIKE ?", "%#{query}%").map { |environment| environment.name }
    end

    sig { params(source: RuleEngine::Types::RuleSource).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.merge_queue_merge_methods_for(source)
      return [] unless source.is_a?(::Repository)

      settings = source.async_allowable_merge_methods.sync

      MergeQueues::IConfiguration::MergeMethod.values.map do |merge_method|
        value = {
          label: RuleEngine::Rules::MergeQueueRule::Configuration.label_for_merge_method(merge_method),
          value: merge_method.serialize.upcase
        }

        setting = settings.get(merge_method)
        if setting.allowed?
          value.merge(enabled: true)
        elsif setting.error?
          value.merge(enabled: false, disabled_reason: "Failed to load repository settings.")
        else
          value.merge(enabled: false, disabled_reason: "Not enabled for this repository.")
        end
      end
    end

    sig do
      params(
        source: RuleEngine::Types::RuleSource
      )
      .returns(T::Array[User])
    end
    def self.insights_users_for(source)
      actor_ids_with_type = if source.is_a?(::Repository)
        RuleEngine::RuleSuite
          .where(repository: source, actor_type: %w[User PublicKey])
          .distinct
          .pluck(:actor_id, :actor_type)
      elsif source.is_a?(::Organization)
        RuleEngine::RuleSuite
          .where(owner: source)
          .where(actor_type: %w[User PublicKey])
          .distinct
          .pluck(:actor_id, :actor_type)
      end

      return [] unless actor_ids_with_type&.any?

      users_with_type, public_keys_with_type = actor_ids_with_type.partition { |_, actor_type| actor_type == "User" }
      user_ids = users_with_type.map(&:first)
      public_key_ids = public_keys_with_type.map(&:first)

      if public_key_ids.any?
        keys = PublicKey.where(id: public_key_ids).includes(:repository)
        key_owner_ids = keys.map { |key| key.deploy_key? ? key.verifier_id : key.user_id }
        user_ids = user_ids.concat(key_owner_ids)
      end

      User.where(id: user_ids).order(:login).compact.to_a
    end

    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        current_user: User,
        query: T.nilable(String),
        limit: T.nilable(Integer)
      )
      .returns(T::Array[{ id: Integer, name: String, type: Symbol, preferred_avatar_url: String }])
    end
    def self.teams_for(source, current_user, query: nil, limit: nil)
      return [] if source.is_a?(Business)

      organization = nil
      repository = nil
      lower_query = query&.downcase

      if source.is_a?(Organization)
        organization = source
      elsif source.in_organization?
        organization = T.cast(source.owner, Organization) if source.owner.is_a?(Organization)
        repository = source
      else
        # Teams are not available without some connection to an Organization
        return []
      end

      teams = []
      T.must(organization).visible_teams_for(current_user).each do |team|
        next if team.secret?
        team_to_add = {
          id: team.id,
          name: team.name,
          type: :Team,
          preferred_avatar_url: T.let(team.primary_avatar_url(20), String)
        }
        if lower_query.present?
          if team.name.downcase.start_with?(lower_query)
            teams.unshift(team_to_add)
          elsif team.name.downcase.include?(lower_query)
            teams.push(team_to_add)
          end
        else
          teams.push(team_to_add)
        end
      end

      teams = teams.first(limit) unless limit.nil?

      teams
    end

    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        current_user: User,
        query: T.nilable(String),
        limit: T.nilable(Integer)
      )
      .returns(T::Array[{ id: Integer, name: String, type: Symbol, preferred_avatar_url: String }])
    end
    def self.enterprise_teams_for(source, current_user, query: nil, limit: nil)
      return [] unless source.is_a?(Business) &&
                       source.enterprise_teams_enabled? &&
                       source.enterprise_rulesets_enabled? &&
                       source.enterprise_rulesets_enterprise_teams_enabled? &&
                       source.enterprise_teams.any?

      lower_query = query&.downcase
      teams = []

      source.enterprise_teams.each do |team|
        team_to_add = {
          id: team.id,
          name: team.name,
          type: :EnterpriseTeam,
          preferred_avatar_url: nil, # enterprise teams don't appear to support avatars yet
        }

        if lower_query.present?
          if team.name.downcase.start_with?(lower_query)
            teams.unshift(team_to_add)
          elsif team.name.downcase.include?(lower_query)
            teams.push(team_to_add)
          end
        else
          teams.push(team_to_add)
        end
      end

      teams = teams.first(limit) unless limit.nil?
      teams
    end

    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        current_user: User,
        query: T.nilable(String),
        exclude_integrations: T.nilable(T::Boolean)
      )
      .returns(T::Array[{ actorId: Integer, actorType: Symbol, name: String, preferred_avatar_url: T.nilable(String), owner: T.nilable(String) }])
    end
    def self.bypass_actors_for(source, current_user, query: nil, exclude_integrations: false)
      org_roles = get_org_roles(query)

      deploy_keys = get_deploy_key(query)

      base_roles = get_base_roles(query)
      custom_roles = get_custom_roles(source, query)
      teams = teams_for(source, current_user, query: query, limit: TEAMS_BYPASS_LIMIT).map do |team|
        {
          actorId: team[:id],
          actorType: :Team,
          name: team[:name],
          preferred_avatar_url: team[:preferred_avatar_url],
          owner: nil,
        }
      end

      enterprise_owner = get_enterprise_owner(source, query)

      enterprise_teams = enterprise_teams_for(source, current_user, query: query, limit: TEAMS_BYPASS_LIMIT).map do |team|
        {
          actorId: team[:id],
          actorType: team[:type],
          name: team[:name],
          preferred_avatar_url: team[:preferred_avatar_url],
          owner: nil,
        }
      end

      integrations = []
      integrations = integrations_for(source, query: query).map do |integration|
        owner = integration[:owner]

        {
          actorId: integration[:id],
          actorType: :Integration,
          name: integration[:name],
          preferred_avatar_url: integration[:preferred_avatar_url],
          owner:,
        }
      end unless exclude_integrations

      enterprise_owner + org_roles + deploy_keys + base_roles + custom_roles + teams + integrations + enterprise_teams
    end

    sig do
      params(organization: Organization, query: String, exclude_public_repos: T::Boolean)
      .returns(T::Array[T::Hash[Symbol, String]])
    end
    def self.repos_for(organization, query, exclude_public_repos = false)
      matching_repos = []
      if query.present?
        scope = Repository.active.where(owner_id: organization.id)
        scope = scope.where(public: false) if exclude_public_repos
        scope = scope.includes(:owner)
        exact_match = scope.where("repositories.name = :query", query: query).first

        scope = scope.where("repositories.name like :query", query: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
        if scope.present? && scope.any?
          scope = scope.order("repositories.name").limit(MAX_SUGGESTIONS)

          matching_repos = scope.to_a
          matching_repos = matching_repos.prepend(exact_match) if exact_match
          matching_repos = matching_repos.uniq.compact
        end
      else
        scope = Repository.active.where(owner_id: organization.id)
        scope = scope.where(public: false) if exclude_public_repos
        scope = scope.includes(:owner)
        matching_repos = scope.recently_updated.order("repositories.name").limit(MAX_SUGGESTIONS)
      end

      matching_repos.map { |repo| RulesEngine::ReactPayload.simple_repository_payload(repo) }
    end

    sig do
      params(enterprise: Business, query: String)
      .returns(T::Array[T::Hash[Symbol, String]])
    end
    def self.orgs_for(enterprise, query)
      matching_repos = []
      if query.present?
        scope = enterprise.organizations.active
        exact_match = scope.where("users.login = :query", query: query).first

        scope = scope.where("users.login like :query", query: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
        if scope.present? && scope.any?
          scope = scope.order("users.login").limit(MAX_SUGGESTIONS)

          matching_orgs = scope.to_a
          matching_orgs = matching_orgs.prepend(exact_match) if exact_match
          matching_orgs = matching_orgs.uniq.compact
        end
      else
        scope = enterprise.organizations.active
        matching_orgs = scope.order("users.login").limit(MAX_SUGGESTIONS)
      end

      matching_orgs&.map { |org| RulesEngine::ReactPayload.simple_organization_payload(org) } || []
    end

    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        resources: T::Array[String],
        min_action: Symbol,
        query: T.nilable(String),
      )
      .returns(T::Array[{ id: Integer, name: String, preferred_avatar_url: String, owner: String }])
    end
    def self.integrations_for(
      source,
      resources: Repository::Resources.subject_types,
      min_action: :write,
      query: nil
    )
      trace_time("suggestions.integrations", tags: ["type:installed_with_#{min_action}_access", "source:#{source.class.name}"]) do
        integrations = T.let([], T::Array[{ id: Integer, name: String, preferred_avatar_url: String, owner: String }])

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
            limit = (limit * (GitHub.flipper[:dont_check_repos_integrations_limit_value].percentage_of_time_value / 100)).to_i
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
          return []
        end

        candidates = (installations || IntegrationInstallation.none).user_installable

        GitHub::PrefillAssociations.prefill_associations(candidates, [:integration])

        lower_query = query&.downcase
        candidates = candidates.filter do |installation|
          installation.integration.name.downcase.include?(lower_query)
        end unless lower_query.blank?

        if self.dependabot_can_bypass(source) && (lower_query.blank? || GitHub.dependabot_github_app_name.downcase.include?(lower_query))
          GitHub::PrefillAssociations.prefill_associations(candidates, [integration: [:owner]])

          integrations << {
            id: GitHub.dependabot_github_app.id,
            name: GitHub.dependabot_github_app.name,
            preferred_avatar_url: GitHub.dependabot_github_app.preferred_avatar_url,
            owner: GitHub.dependabot_github_app.owner.display_login,
          }
        end

        candidates.each do |installation|
          integrations << {
            id: installation.integration.id,
            name: installation.integration.name,
            preferred_avatar_url: installation.integration.preferred_avatar_url,
            owner: installation.integration.owner.display_login,
          }
        end

        integrations
          .flatten
          .uniq { |integration| integration[:id] }
          .sort_by { |integration| integration[:name] }
      end
    end

    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        request_type: T.nilable(String),
      )
      .returns(T::Array[User])
    end
    def self.bypass_requests_requesters_for(source, request_type = nil)
      query = if source.is_a?(Organization)
        #TODO: Replace with org_id when available
        rule_suites_by_org_owner_ids = RuleEngine::RuleSuite
        .where(owner: source)
        .for_ruleset_source(source).ids

        return [] unless rule_suites_by_org_owner_ids.any?

        Exemptions::ExemptionRequest
        .where("exemption_requests.resource_owner_type = 'RuleEngine::RuleSuite'")
        .where("exemption_requests.resource_owner_id IN (?)", rule_suites_by_org_owner_ids)
      else
        Exemptions::ExemptionRequest.where(repository: source)
      end.where(created_at: 1.month.ago..)
      query = query.where(request_type:) unless request_type.nil?
      requester_ids = query.distinct.pluck(:requester_id)

      return [] unless requester_ids&.any?

      User.where(id: requester_ids).order(:login).compact.to_a
    end

    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        request_type: T.nilable(String),
      )
      .returns(T::Array[User])
    end
    def self.bypass_requests_approvers_for(source, request_type = nil)
      query = Exemptions::ExemptionResponse.joins(:exemption_request)
      query = if source.is_a?(Organization)
        #TODO: Replace with org_id when available
        rule_suites_by_org_owner_ids = RuleEngine::RuleSuite
        .where(owner: source)
        .for_ruleset_source(source).ids

        return [] unless rule_suites_by_org_owner_ids.any?

        request_ids = query.where("exemption_requests.resource_owner_type = 'RuleEngine::RuleSuite'")
        .where("exemption_requests.resource_owner_id IN (?)", rule_suites_by_org_owner_ids)
        .select("exemption_requests.id")

        return [] unless request_ids.any?

        query.where(exemption_requests: { id: request_ids, created_at: 1.month.ago.. })
      else
        query.where(exemption_requests: { repository: source, created_at: 1.month.ago.. })
      end

      query = query.where(exemption_requests: { request_type: }) unless request_type.nil?
      reviewer_ids = query.pluck(:reviewer_id)

      return [] unless reviewer_ids&.any?

      User.where(id: reviewer_ids).order(:login).compact.to_a
    end

    sig do
      params(query: T.nilable(String)).returns(T::Array[{
        actorId: Integer,
        actorType: Symbol,
        name: String,
        preferred_avatar_url: NilClass,
        owner: NilClass,
      }])
    end
    private_class_method def self.get_base_roles(query)
      lower_query = query&.downcase
      repository_admin_name = "Repository admin"

      @cached_base_roles ||= T.let(RepositoryRole.where(owner_id: nil, name: RepositoryRulesetBypassActor::ALLOWED_BASE_ROLES), T.untyped)
      return_array = []
      @cached_base_roles.filter_map do |role|
        next if lower_query.present? && !repository_admin_name.downcase.include?(lower_query)
        next unless role.name == "admin"
        return_array.push(
          {
            actorId: role.id,
            actorType: :RepositoryRole,
            name: repository_admin_name,
            preferred_avatar_url: nil,
            owner: nil,
          }
        )
      end
      @cached_base_roles.filter_map do |role|
        next if lower_query.present? && !role.name.downcase.include?(lower_query)
        next unless role.name != "admin"
        return_array.push(
          {
            actorId: role.id,
            actorType: :RepositoryRole,
            name: role.name.humanize,
            preferred_avatar_url: nil,
            owner: nil,
          }
        )
      end
      return_array
    end

    sig do
      params(source: RuleEngine::Types::RuleSource, query: T.nilable(String)).returns(T::Array[{
        actorId: Integer,
        actorType: Symbol,
        name: String,
        preferred_avatar_url: NilClass,
        owner: NilClass,
      }])
    end
    private_class_method def self.get_custom_roles(source, query)
      if source.is_a?(Organization)
        corresponding_org = source
      else
        org_owner = Repository.where(id: source[:id]).org_owned.pluck(:owner_id)
        if org_owner
          corresponding_org = Organization.where(id: org_owner[0])[0]
        else
          []
        end
      end
      lower_query = query&.downcase
      RepositoryRole.custom_roles_for_org(corresponding_org).filter_map do |role|
        next if lower_query.present? && !role.name.downcase.include?(lower_query)
        {
          actorId: T.must(role.id),
          actorType: :RepositoryRole,
          name: role.name,
          preferred_avatar_url: nil,
          owner: nil,
        }
      end
    end

    sig do
      params(query: T.nilable(String)).returns(T::Array[{
        actorId: Integer,
        actorType: Symbol,
        name: String,
        preferred_avatar_url: NilClass,
        owner: NilClass,
      }])
    end
    private_class_method def self.get_org_roles(query)
      org_roles = []
      org_admin_name = "Organization admin"
      lower_query = query&.downcase

      if !lower_query || org_admin_name.downcase.include?(lower_query)
        org_roles.push(
          {
            actorId: 1,
            actorType: :OrganizationAdmin,
            name: org_admin_name,
            preferred_avatar_url: nil,
            owner: nil,
          }
        )
      end
      org_roles
    end

    sig do
      params(source: RuleEngine::Types::RuleSource, query: T.nilable(String)).returns(T::Array[{
        actorId: Integer,
        actorType: Symbol,
        name: String,
        preferred_avatar_url: NilClass,
        owner: NilClass,
      }])
    end
    private_class_method def self.get_enterprise_owner(source, query)
      return [] unless source.enterprise_owner_bypass_enabled?
      enterprise = source.is_a?(Business) ? source : source.business
      return [] unless enterprise

      lower_query = query&.downcase
      name = "Enterprise owners"

      if lower_query.nil? || name.downcase.include?(lower_query)
        [{
          actorId: enterprise.id,
          actorType: :EnterpriseOwner,
          name: name,
          preferred_avatar_url: nil,
          owner: nil,
        }]
      else
        []
      end
    end

    sig do
      params(query: T.nilable(String)).returns(T::Array[{
        actorId: Integer,
        actorType: Symbol,
        name: String,
        preferred_avatar_url: NilClass,
        owner: NilClass,
      }])
    end
    private_class_method def self.get_deploy_key(query)
      lower_query = query&.downcase
      name = RepositoryRulesetBypassActor::DeployKey.name
      deploy_key_bypass_actor = RepositoryRulesetBypassActor.new_deploy_key_bypass_actor
      if lower_query.nil? || name.downcase.include?(lower_query)
        return [{
          actorId: deploy_key_bypass_actor.actor_id,
          actorType: deploy_key_bypass_actor.actor_type.to_sym,
          name:,
          preferred_avatar_url: nil,
          owner: nil,
        }]
      end
      []
    end

    sig do
      params(source: RuleEngine::Types::RuleSource).
      returns(T::Boolean)
    end
    private_class_method def self.dependabot_can_bypass(source)
      source.is_a?(Business) || source.dependabot_installed?
    end
  end
end
