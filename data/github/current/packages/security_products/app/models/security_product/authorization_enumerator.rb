# typed: true
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityProduct

  # This class encapsulates the authorization logic that determines the repositories
  # for which a user is authorized to view and resolve security feature alerts by specified action FGPs.
  #
  # TODO: There is significant conceptual and business-logic overlap with the
  # Repository::VulnerabilityManagement class. At a future point, it would
  # probably be fitting to unify alerting auth logic into a single entry point
  class AuthorizationEnumerator
    include GitHub::Memoizer
    include GitHub::SecurityCenter::LoggingHelper
    include Scientist

    SUPPORTED_ACTIONS = [
      :view_secret_scanning_alerts,
      :read_code_scanning,
      :view_dependabot_alerts,
      :resolve_secret_scanning_alerts
    ].freeze

    # Internal and custom roles create explicit role_permissions records in the DB that we can query
    # to enumerate the FGPs granted by them. Unfortunately system roles like :write only create abilities records.
    # Instead of making extra join queries to dynamically enumerate the FGPs granted by system roles,
    # we list them here to optimize our search.
    SYSTEM_ROLES_TO_IMPLICITLY_GRANTED_ACTIONS = {
      write: [:read_code_scanning, :view_dependabot_alerts].freeze,
    }.freeze

    DEFAULT_OPTIONS = {
      organization: nil,
      repository_ids: nil,
      include_oauth_restriction: true,
      include_indirect_forks: true,
      include_oopfs: true,
    }

    def self.for_dependabot(user)
      new(user: user, actions: [:view_dependabot_alerts])
    end

    attr_reader :user, :actions, :options

    ##
    # Create an instance of AuthorizationEnumerator
    #
    # @param user [User]              The user for whom to evaluate access.
    # @param actions [Array<Symbol>]  The array of fine-grained permissions for which to evaluate access.
    # @param options [Hash]           Optional arguments to control scope of access evaluation.
    #     organization [Organization]               Return repositories within the given organization. Default nil.
    #     repository_ids [Array<Integer>]           The set of candidate repositories. Default nil.
    #     include_oauth_restriction: [Boolean]      See User#associated_repository_ids. Default true.
    #     include_indirect_forks: [Boolean]         See User#associated_repository_ids. Default true.
    #     include_oopfs: [Boolean]                  See User#associated_repository_ids. Default true.
    def initialize(user:, actions:, options: {})
      raise ArgumentError, "Must provide a user" unless user.is_a?(User)
      raise ArgumentError, "Must provide an array of supported FGP symbols" unless actions.is_a?(Array)
      raise ArgumentError, "Must provide an array of supported FGP symbols" unless (actions - SUPPORTED_ACTIONS).empty?

      @user = user
      @actions = actions
      @options = DEFAULT_OPTIONS.merge(options)
      @options[:repository_ids] = @options[:repository_ids].uniq if @options[:repository_ids]
    end

    # enumerate actions for actor/subject(s)
    #  - confirm actor has fgp(s) in repo(s)
    def authorized_repository_ids_by_action
      # {
      #   view_dependabot_alerts: [1, 2, 3],
      #   view_secret_scanning_alerts: [2, 5]
      # }
      authorizations
        .reduce({}) do |memo, (action, repo_id)|
          action_sym = action.to_sym
          memo[action_sym] ||= []
          memo[action_sym] << repo_id
          memo
        end
        .each { |_, v| v.uniq! }
    end

    # enumerate subjects for actor/action
    #  - all repos where user has :view_dependabot_alerts
    def authorized_repository_ids
      authorizations.map(&:second).uniq
    end

    def authorized_repositories
      Repository.where(id: authorized_repository_ids)
    end

    private

    def authorizations
      return @authorizations if defined?(@authorizations)

      result = []

      datadog_tags = [
        "has_organization:#{options[:organization].present?}",
        "has_repository_ids:#{options[:repository_ids].present?}",
      ]

      GitHub.dogstats.distribution("security_center.auth_enumeration.candidate_repositories.count", options[:repository_ids]&.length || 0, tags: datadog_tags)

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:user_team_ids"]) do
        # force loading this data here, so that we can track it independently from further uses of the memoized result
        GitHub.dogstats.distribution("security_center.auth_enumeration.candidate_teams.count", user_team_ids.length, tags: datadog_tags)
      end

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:repo_admin"]) do
        # All of the repositories to which this user has admin access…
        result << actions.product(adminable_repository_ids)
      end

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:access_to_alerts", "scope:user"]) do
        # …plus those to which this user was explicitly added to Access to Alerts
        result << actions.product(access_to_alerts_user_repository_ids)
      end

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:access_to_alerts", "scope:team"]) do
        # …plus those to which one of this user's teams was explicitly added to Access to Alerts
        result << actions.product(access_to_alerts_team_repository_ids)
      end

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:all_repo_fgp", "scope:user"]) do
        # …plus those in which the user has been granted access to view alerts via all repo role FGPs
        result << all_repo_permissions(actor_type: "User", actor_id: user.id)
      end

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:all_repo_fgp", "scope:team"]) do
        # …plus those in which one of this user's teams has been granted access to view alerts via all repo role FGPs
        result << all_repo_permissions(actor_type: "Team", actor_id: user_team_ids)
      end

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:all_repo_fgp", "scope:team"]) do
        # …plus those in which one of this user's teams has been granted access to view alerts via all repo role FGPs
        result << all_repo_permissions(actor_type: "BusinessTeam", actor_id: user_business_team_ids)
      end

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:fgp", "scope:user"]) do
        # …plus those in which the user has been granted access to view alerts via FGPs
        result << view_permissions_via_user
      end

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:fgp", "scope:team"]) do
        # …plus those in which one of this user's teams has been granted access to view alerts via FGPs
        result << view_permissions_via_team
      end

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:ability", "scope:user"]) do
        # …plus those in which the user has a system role that corresponds to an FGP
        result << system_role_fgps_via_user
      end

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.dist", tags: datadog_tags + ["method:ability", "scope:team"]) do
        # …plus those in which one of this user's teams has a system role that corresponds to an FGP
        result << system_role_fgps_via_team
      end

      # [ [[:a, 1], [:b, 2]], [[:c, 1]] ] => [[:a, 1], [:b, 2]], [[:c, 1]]
      @authorizations = result.reduce(&:concat).uniq
    end

    def adminable_repository_ids
      filter = { min_action: :admin }
      filter[:organization] = options[:organization] if options.key?(:organization)
      filter[:repository_ids] = options[:repository_ids] if options.key?(:repository_ids)
      filter[:include_oauth_restriction] = options[:include_oauth_restriction] if options.key?(:include_oauth_restriction)
      filter[:include_indirect_forks] = options[:include_indirect_forks] if options.key?(:include_indirect_forks)
      filter[:include_oopfs] = options[:include_oopfs] if options.key?(:include_oopfs)
      user.associated_repository_ids(filter) # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    end

    def access_to_alerts_user_repository_ids
      ability_subject_ids(
        actor_type: "User",
        actor_id: user.id,
        subject_type: "Repository::VulnerabilityManagement",
        priority: Ability.priorities[:direct],
        fn: __method__,
      )
    end

    def access_to_alerts_team_repository_ids
      if erp_enterprise_teams_org_roles_enabled_for_user
        actor_type = %w(Team BusinessTeam)
      else
        actor_type = "Team"
      end
      ability_subject_ids(
        actor_type: actor_type,
        actor_id: user_team_ids,
        subject_type: "Repository::VulnerabilityManagement",
        priority: Ability.priorities[:direct],
        fn: __method__,
      )
    end

    def all_repo_permissions(actor_type:, actor_id:)
      target_ids =
        if options[:organization]
          if actor_type == "BusinessTeam"
            if options[:organization].business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
              Array.wrap(options[:organization].id)
            else
              []
            end
          else
            Array.wrap(options[:organization].id)
          end
        elsif actor_type == "User"
          @user.organization_ids
        elsif actor_type == "Team"
          user_teams.map(&:organization_id).uniq
        elsif actor_type == "BusinessTeam"
          Orgs.domain.teams.business_team_org_ids_for_user(user_id: @user.id, team_ids: actor_id)
        end

      return [] if target_ids.nil? || target_ids.empty? || actor_id.nil? || (actor_id.is_a?(Array) && actor_id.empty?)

      result = Authz.domain.user_roles.actors_permissions_for_orgs(
        target_ids:,
        actions:,
        actor_type:,
        actor_id: actor_id.is_a?(Integer) ? [actor_id] : actor_id,
      )

      repos = Repository.where(owner_id: result.map(&:second)).pluck(:owner_id, :id)
      org_to_repos = Hash.new { |h, k| h[k] = [] }.tap do |h|
        repos.each { |(owner_id, repo_id)| h[owner_id] << repo_id }
      end

      # apply repo as a post filter to keep from bloating the query unnecessarily
      org_to_repos.transform_values! { |repo_ids| options[:repository_ids] & repo_ids } if options[:repository_ids]

      result.flat_map { |(action, org_id)| [action].product org_to_repos[org_id] }
    end

    def view_permissions_via_user
      filter = {
        actor_type: "User",
        actor_id: user.id,
        target_type: "Repository",
        role_permissions: { action: actions },
      }
      filter[:role] = { owner_id: options[:organization].id, owner_type: "Organization" } if options[:organization]

      result = UserRole
        .joins(role: [:permissions])
        .where(filter)
        .pluck(:action, :target_id)

      # apply repo as a post filter to keep from bloating the query unnecessarily
      result.select! { |_, repo_id| options[:repository_ids].include?(repo_id) } if options[:repository_ids]

      result
    end

    def view_permissions_via_team
      if erp_enterprise_teams_org_roles_enabled_for_user
        actor_type = %w(Team BusinessTeam)
      else
        actor_type = "Team"
      end

      filter = {
        actor_type: actor_type,
        actor_id: user_team_ids,
        target_type: "Repository",
        role_permissions: { action: actions },
      }
      filter[:role] = { owner_id: options[:organization].id, owner_type: "Organization" } if options[:organization]

      rel = UserRole.joins(role: [:permissions]).where(filter)

      return rel.pluck(:action, :target_id) unless options[:repository_ids]

      results_by_repo = rel.pluck(:action, :target_id).group_by { |i| i[1] }
      options[:repository_ids].flat_map { |id| results_by_repo[id] || [] }
    end

    def system_role_fgps_via_user
      system_role = :write
      system_role_fgps = SYSTEM_ROLES_TO_IMPLICITLY_GRANTED_ACTIONS[system_role]

      return [] unless (actions & system_role_fgps).any?

      repo_ids = []

      # Repositories to which the user has been granted the system role
      repo_ids.concat(
        ability_subject_ids(
          actor_type: "User",
          actor_id: user.id,
          subject_type: "Repository",
          action: system_role,
          fn: __method__,
        )
      )

      # Handles base system role to an organization’s repositories
      target_organizations = options[:organization] ? [options[:organization].id] : user.organization_ids
      repo_ids.concat(
        ability_subject_ids(
          actor_type: "Organization",
          actor_id: target_organizations,
          subject_type: "Repository",
          action: system_role,
          priority: Ability.priorities[:direct],
          fn: __method__,
        )
      )

      system_role_fgps.product(repo_ids.uniq)
    end

    def erp_enterprise_teams_org_roles_enabled_for_user
      user.async_businesses.then do |businesses|
        businesses.any? { |business| business&.erp_feature_enabled?(:enterprise_teams_org_roles) }
      end.sync
    end

    def system_role_fgps_via_team
      system_role = :write
      system_role_fgps = SYSTEM_ROLES_TO_IMPLICITLY_GRANTED_ACTIONS[system_role]

      return [] unless (actions & system_role_fgps).any?

      if erp_enterprise_teams_org_roles_enabled_for_user
        actor_type = %w(Team BusinessTeam)
      else
        actor_type = "Team"
      end
      repo_ids = ability_subject_ids(
        actor_type: actor_type,
        actor_id: user_team_ids,
        subject_type: "Repository",
        action: system_role,
        fn: __method__,
      )

      system_role_fgps.product(repo_ids)
    end

    def ability_subject_ids(
      actor_type:,
      actor_id:,
      subject_type:,
      priority: nil,
      action: nil,
      fn: nil
    )
      filter = {
        actor_type: actor_type,
        actor_id: actor_id,
        subject_type: subject_type,
      }
      filter[:priority] = priority if priority.present?
      filter[:action] = action if action.present?

      has_repository_ids = !options[:repository_ids].nil?
      datadog_tags = [
        "actor_type:#{filter[:actor_type]}",
        "subject_type:#{filter[:subject_type]}",
        "has_repository_ids:#{has_repository_ids}",
        ("action:#{filter[:action]}" if filter[:action]),
        ("priority:#{filter[:priority]}" if filter[:priority]),
        ("fn:#{fn}" if fn),
      ].compact_blank!

      GitHub.dogstats.distribution_time("security_center.auth_enumeration.ability_subject_ids.dist", tags: datadog_tags) do
        subject_ids = Ability.where(filter).pluck(:subject_id)
        if has_repository_ids
          subject_ids & options[:repository_ids]
        else
          subject_ids
        end
      end
    end

    memoize def user_teams
      if options[:organization]
        options[:organization].teams_for(user).flat_map { |team| [team] + team.ancestors }
      else
        user.teams(with_ancestors: true)
      end
    end

    memoize def user_business_team_ids
      if options[:organization]
        Orgs.domain.teams.business_team_ids_with_assigned_orgs_for(user_id: user.id, organization_id: options[:organization].id)
      else
        # batch size default is 1_000
        Ability.batched_scope(:actor_id, values: [user.id]) do |scope|
          scope.where(actor_type: "User", subject_type: "BusinessTeam")
        end.pluck(:subject_id)
      end
    end

    memoize def user_team_ids
      ids = erp_enterprise_teams_org_roles_enabled_for_user ? user_business_team_ids : []
      ids += user_teams.map(&:id)
    end

    instrument_method \
      :adminable_repository_ids,
      :access_to_alerts_user_repository_ids,
      :access_to_alerts_team_repository_ids,
      :all_repo_permissions,
      :view_permissions_via_user,
      :view_permissions_via_team,
      :system_role_fgps_via_user,
      :system_role_fgps_via_team
  end
end
