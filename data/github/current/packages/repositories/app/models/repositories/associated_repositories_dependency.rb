# typed: true
# frozen_string_literal: true

module Repositories::AssociatedRepositoriesDependency
  extend T::Helpers

  requires_ancestor { User }

  # Check whether the given repository is associated with this user.
  # options is the same as defined for associated_repository_ids
  def async_associated_repository?(repository_id, options = {})
    Platform::Loaders::AssociatedRepositoryCheck.load(self, repository_id, **options)
  end

  # Public: Return a list of repository IDs associated with this user.
  #
  # Includes repositories that are:
  #
  # :owned    - owned by the user, which includes both root repos and forks
  # :direct   - repositories where the user is a direct collaborator
  # :indirect - repositories where the user is a collaborator either via admin
  #             on an organization, or has access to the repo via a team
  #
  # Arguments:
  #
  # min_action: - An optional Symbol representing the minimum ability action
  #               (:read, :write, or :admin) that the user must have for the
  #               returned repositories. Default is nil, for no min_action
  #               restrictions.
  # including:  - An optional Array of Symbols representing the way that the
  #               user is associated with the returned repositories. Default is
  #               nil, which means "all". Valid values are :owned, :direct, and
  #               :indirect.
  # exclude_public: Optional flag to exclude public repos in results. Defaults to false,
  #               and not compatible with a min_action > :read.
  # include_oauth_restriction: - Optional flag to enable or disable oauth
  #               application restrictions when querying for associated
  #               repositories. Defaults to true.
  # include_indirect_forks: - Optional flag to enable or disable the loading of
  #               user-owned forks of organization-owned repositories that the
  #               user has access to through their organization membership (such
  #               as through a user-owned fork being added to a team). Defaults
  #               to true
  # include_oopfs: - Optional flag to enable or disable the loading of
  #               organization-owned forks of private organization-owned
  #               repositories where the user is an owner of the root
  #               organization.
  # resource:     - An optional String to represent a child association.
  #               Accepted by this method for consistent calls with
  #               Bot#associated_repository_ids, but currently not used for Users.
  # repository_ids: An optional list of candidate repository ids. Only
  #                 repositories that are in this list and are associated with
  #                 the user will be returned.
  # organization: - An optional Organization to limit results to. When organization
  #                 is specified, checks for indirect_via_adminship,
  #                 org_owned_forks_of_private_org_owned_repos, indirect_via_all_repo_role
  #                 and indirect_via_business_team_org_association can be scoped to that org to improve performance.
  #
  # Returns an Array of Integer repository IDs.
  def associated_repository_ids(options = {})
    defaults = {
      min_action: nil,
      including: nil,
      exclude_public: false,
      include_oauth_restriction: true,
      include_indirect_forks: true,
      include_oopfs: true,
      resource: nil,
      repository_ids: nil,
      organization: nil,
    }
    invalid_keys = options.keys - defaults.keys
    if invalid_keys.any?
      raise ArgumentError, "Invalid options: #{invalid_keys.join(', ')}"
    end

    options_with_defaults = options.reverse_merge(defaults)
    if options_with_defaults == defaults
      # Memoize the IDs if no options were overridden
      return @default_associated_repository_ids if defined?(@default_associated_repository_ids)
      @default_associated_repository_ids = fetch_associated_repository_ids(options_with_defaults)
    else
      # Don't memo-ize if options were overridden
      fetch_associated_repository_ids(options_with_defaults)
    end
  end

  private def fetch_associated_repository_ids(options)
    filter = AssociatedRepositories.new(self,
      **options.slice(:min_action, :including, :exclude_public, :include_indirect_forks, :include_oopfs, :repository_ids, :organization),
    )

    if governed_by_oauth_application_policy? && options[:include_oauth_restriction]
      Repository.oauth_app_policy_approved_repository_ids(repository_ids: filter.ids, app: oauth_application)
    else
      filter.ids
    end
  end

  # Public: Return a list of repository IDs this site admin has unlocked.
  #
  # Returns an Array of Integer Repository IDs.
  def unlocked_repository_ids
    return [] unless can_unlock_repos?
    RepositoryUnlock.active_for_user(self).pluck(:repository_id)
  end

  # Public: Returns a symbol representing this User's relationship to the given Repository.
  #
  # repo - a Repository
  #
  # Returns one of :owner, :member, or :none.
  def relationship_to(repo)
    if repo.owner == self
      :owner
    elsif repo.member?(self)
      :member
    else
      :none
    end
  end

  # Internal: Filter and retrieve the set of repositories associated with a
  # user.
  class AssociatedRepositories
    include Scientist

    class AdminnedOrgIdActor
      include GitHub::FlipperActor
      include GitHub::VexiActor

      def initialize(organization_id)
        @organization_id = organization_id
      end

      def flipper_id
        "Organization:#{@organization_id}"
      end

      def vexi_id
        flipper_id
      end
    end

    DEFAULT_INCLUDING_VALUES = [:owned, :direct, :indirect].freeze
    VALID_INCLUDING_VALUES = (DEFAULT_INCLUDING_VALUES + [:indirect_via_adminship, :indirect_via_membership, :indirect_via_all_repo_role, :indirect_via_business_team_org_association]).freeze
    RUBY_INTERSECTION_THRESHOLD = 8_000
    COUNT_BRACKET = 1_000
    COUNT_BRACKET_LIMIT = 20
    BATCH_THRESHOLD = 1_000

    attr_reader :user
    attr_reader :min_action
    attr_reader :including
    attr_reader :organization

    def initialize(user, repository_ids: nil, min_action: nil, including: nil, exclude_public: false, include_indirect_forks: true, include_oopfs: true, organization: nil)
      @user = user

      @repository_ids = repository_ids

      @min_action = min_action
      validate_min_action(@min_action)

      @including = including ? Array(including) : DEFAULT_INCLUDING_VALUES
      validate_including(@including)

      @exclude_public = exclude_public
      @include_indirect_forks = include_indirect_forks
      @include_oopfs = include_oopfs

      @organization = organization
    end

    # We can exclude public repos from the scope when:
    # - the caller has specifically requested it
    # - the caller has not requested any access level greater than read; the assumption
    #   is that the caller will handle loading public repos separately, in which case an
    #   explicit association with read permissions is redundant.
    def exclude_public_repos?
      @exclude_public && (min_action.nil? || min_action == :read)
    end

    def ids
      return [] if user.new_record?

      tags = T.let([], T::Array[String])

      begin
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        tags = {
          includes_repository_ids: !!@repository_ids,
          use_db_repository_filter: use_db_repository_filter?,
          includes_organization: !!@organization,
          org_admin:  !!(@organization && @organization.adminable_by?(user)),
          many_repos: many_repos?,
        }.map { |k, v| "#{k}:#{v}" }

        result =
          GitHub.dogstats.distribution_time("associated_repository_ids.calculate_ids.dist", tags: tags) do
            calculate_ids
          end
      ensure
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        tags += ["include_repo_count_bracket:#{count_bracket(@repository_ids)}", "result_count_bracket:#{count_bracket(result)}", "including:#{@including.sort}", "min_action:#{@min_action || :undefined}", "include_indirect_forks:#{@include_indirect_forks}", "include_oopfs:#{@include_oopfs}"]
        GitHub.dogstats.distribution("associated_repository_ids.dist", (end_time - T.must(start_time)) * 1_000, tags: tags)
      end
    end

    private

    def count_bracket(collection)
      return 0 unless collection.present?
      bracket = collection.count / COUNT_BRACKET
      return bracket if bracket < COUNT_BRACKET_LIMIT
      COUNT_BRACKET_LIMIT
    end

    def many_repos?
      !!(@repository_ids && @repository_ids.count > RUBY_INTERSECTION_THRESHOLD)
    end

    # Private: Returns a boolean of whether or not we should be filtering
    # repositories in the database
    def use_db_repository_filter?(repository_ids: nil)
      repository_ids ||= @repository_ids
      !!(repository_ids && repository_ids.count <= RUBY_INTERSECTION_THRESHOLD)
    end

    # Private: Return a boolean of whether or not we should be filtering
    # repositories
    def filtering_repositories?
      @repository_ids.present?
    end

    def calculate_ids
      return [] if @repository_ids && @repository_ids.empty?

      @found_ids = Set.new
      @remaining_needed_ids = filtering_repositories? ? @repository_ids.dup : nil

      query_with_timing(
        query: "with_indirect_grants",
        run_if: include_repositories_with_indirect_grants?,
        stats: GitHub.dogstats,
        incremental: true,
      ) do
        repository_ids_with_indirect_grants(repository_ids: @remaining_needed_ids)
      end

      query_with_timing(
        query: "owned_by_user",
        run_if: include_repositories_owned_by_user?,
        stats: GitHub.dogstats,
        incremental: true,
      ) do
        repository_ids_owned_by_user(repository_ids: @remaining_needed_ids)
      end

      query_with_timing(
        query: "with_direct_grants",
        run_if: include_repositories_with_direct_grants?,
        stats: GitHub.dogstats,
        incremental: true,
      ) do
        repository_ids_with_direct_grants(repository_ids: @remaining_needed_ids)
      end

      query_with_timing(
        query: "org_owned_private_repos_and_forks",
        run_if: include_org_owned_forks_of_private_org_owned_repos?,
        stats: GitHub.dogstats,
        incremental: true,
      ) do
        repository_ids_for_org_owned_private_repos_and_forks(repository_ids: @remaining_needed_ids)
      end

      query_with_timing(
        query: "with_role_grants",
        run_if: include_repositories_with_indirect_via_all_repo_role?,
        stats: GitHub.dogstats,
        incremental: true,
      ) do
        repository_ids_with_all_repo_role_grant(repository_ids: @remaining_needed_ids)
      end

      if user.feature_enabled?(:check_business_team_in_associated_repository_ids)
        query_with_timing(
          query: "with_business_team_grants",
          run_if: include_repositories_with_indirect_via_business_team_org_association?,
          stats: GitHub.dogstats,
          incremental: true,
        ) do
          repository_ids_with_business_team_grant(repository_ids: @remaining_needed_ids)
        end
      end

      # Filter repository_ids in memory if we didn't filter via the database queries
      @found_ids &= @repository_ids if filtering_repositories? && !use_db_repository_filter?

      @found_ids.sort
    end

    # Record timing for the specified associated repo query with one of the following results:
    # - "bypass"     : we are querying for specific repository IDs, and we've found them all so no need to query
    # - "found"      : we are not querying for specific repository IDs, and found some
    # - "empty"      : we are not querying for specific repository IDs, and found none
    # - "overlap"    : we are querying for specific repository IDs, and found some of those and also some others
    # - "partial"    : we are querying for specific repository IDs, and found some but not all of them
    # - "hit"        : we are querying for specific repository IDs, and found them
    # - "dup"        : we are querying for specific repository IDs, and found som were found in earlier queries
    # - "extra"      : we are querying for specific repository IDs, and found some we didn't need
    # - "miss"       : we are querying for specific repository IDs, and found none
    # - "skip"       : this query was disabled
    # - "redundant"  : (deprecated by "bypass") we are querying for specific repository IDs, and found none but they've all been found already
    def query_with_timing(query:, run_if:, stats:, incremental:)
      start_time = GitHub::Dogstats.monotonic_time

      if run_if
        if incremental && filtering_repositories? && @remaining_needed_ids.empty?
          new_ids = []
          result = "bypass"
        else
          new_ids = Set.new yield
          result = if !filtering_repositories?
            new_ids.any? ? "found" : "empty"
          elsif new_ids.none?
            "miss"
          else
            needed_ids = incremental ? @remaining_needed_ids.to_set : @repository_ids.to_set
            if new_ids.intersect?(needed_ids)
              if new_ids.proper_superset?(needed_ids)
                "overlap"
              elsif new_ids.proper_subset?(needed_ids)
                "partial"
              else
                "hit"
              end
            elsif new_ids.intersect?(@found_ids)
              "dup"
            else
              "extra"
            end
          end
        end
      else
        new_ids = []
        result = "skip"
      end

      elapsed_ms = GitHub::Dogstats.duration(start_time)

      tags = [
        "use_repository_filter:#{filtering_repositories?}",
        "use_db_repository_filter:#{use_db_repository_filter?}",
        "query:#{query}",
        "result:#{result}",
        "incremental:#{incremental}",
      ]
      stats.distribution("associated_repository_ids_query.dist", elapsed_ms, tags: tags)

      @remaining_needed_ids -= new_ids.to_a if incremental && filtering_repositories?
      @found_ids += new_ids
    end

    def repository_ids_with_direct_grants(repository_ids: nil)
      repository_ids ||= @repository_ids

      ActiveRecord::Base.connected_to(role: :reading) do
        sql = Arel.sql <<~SQL, actor_id: user.ability_delegate.ability_id, direct: Ability.priorities[:direct]
          SELECT ability.subject_id
          FROM   abilities AS ability
          WHERE ability.actor_id     = :actor_id
          AND   ability.actor_type   = 'User'
          AND   ability.subject_type = 'Repository'
          AND   ability.priority     = :direct
        SQL

        if require_a_minimum_ability_action?
          sql += Arel.sql "AND action >= :min_action", min_action: Ability.actions[min_action]
        end

        if use_db_repository_filter?(repository_ids: repository_ids)
          sql_values = repository_ids.uniq.in_groups_of(BATCH_THRESHOLD, false).flat_map do |batch|
            batch_sql = sql + Arel.sql("AND ability.subject_id IN (:repository_ids)", repository_ids: batch)
            Ability.connection.select_rows(batch_sql).map(&:first)
          end
        else
          sql_values = Ability.connection.select_values(sql)
        end

        if organization
          # Only include direct grants to repos in this org
          scope = Repository.active.owned_by(organization).where(id: sql_values.uniq)
          scope = scope.private_scope if exclude_public_repos?
          scope.ids
        else
          sql_values
        end
      end
    end

    def repository_ids_with_indirect_grants(repository_ids: nil)
      repository_ids ||= @repository_ids

      ids = if organization
        # The membership query can be expensive, and is redundant if
        # the user has admin access to the org's repositories.
        control_ids = repository_ids_indirect_via_adminship(repository_ids: repository_ids)
        if control_ids.any?
          control_ids
        else
          repository_ids_indirect_via_membership(repository_ids: repository_ids)
        end
      else
        control_ids = repository_ids_indirect_via_adminship(repository_ids: repository_ids)
        if repository_ids.nil? || (remaining_ids = repository_ids - control_ids).any?
          control_ids += repository_ids_indirect_via_membership(repository_ids: remaining_ids)
        end
        control_ids
      end

      ids = ids.uniq

      return ids if ids.empty? || organization.present? || include_indirect_forks?

      Repository.active.org_owned.batched_scope(:id, values: ids, batch_size: 10_000).pluck(:id)
    end

    def repository_ids_indirect_via_adminship(repository_ids: nil)
      return [] unless include_repositories_with_indirect_via_adminship?

      repository_ids ||= @repository_ids

      if use_db_repository_filter?(repository_ids: repository_ids)
        if organization
          Repository.accessible_via_org_admin(user, repository_ids, organization.id)
        else
          Repository.accessible_via_org_admin(user, repository_ids)
        end
      else
        if organization
          org_ids_user_admins = Ability.user_admin_on_organization(
            actor_id: user.ability_delegate.ability_id,
            subject_id: organization.id,
          ).pluck(:subject_id)
        else
          # get a list of orgs user admins
          org_ids_user_admins = Ability.user_admin_on_organizations(
            actor_id: user.ability_delegate.ability_id,
          ).pluck(:subject_id)
        end

        # get the repos those orgs own, assuming this includes forks
        if organization
          # When scoping to an org, return only repos owned by the org. This lets us skip the expensive query at the end of
          # repository_ids_with_indirect_grants.
          scope = Repository.where(active: true, organization_id: org_ids_user_admins).where("owner_id = organization_id")
          scope = scope.private_scope if exclude_public_repos?
          scope.pluck(:id)
        else
          Repositories.domain.repo_ids_by_org_ids(org_ids: org_ids_user_admins)
        end
      end
    end

    def repository_ids_indirect_via_membership(repository_ids: nil)
      return [] unless include_repositories_with_indirect_via_membership?

      repository_ids ||= @repository_ids

      ActiveRecord::Base.connected_to(role: :reading) do
        # NOTE: the grandparent subject_type and parent actor_type restrictions
        # being limited to valid connectors is an optimization. If any
        # additional User -> <Connector> -> Repository types are added, they need
        # to be added here.
        #
        # NOTE: when scoping to an org, we still need this parent/grandparent join to
        # include all teams and orgs that the actor is a member of; since those
        # memberships may have ability grants to the scoped org's repositories even
        # if they're a different org, or teams belonging to a different org.
        sql = Arel.sql <<~SQL, actor_id: user.ability_delegate.ability_id, direct: Ability.priorities[:direct], valid_connectors: %w(Team Organization)
          SELECT DISTINCT parent.subject_id
          FROM   abilities AS parent
          JOIN   abilities AS grandparent
          ON     grandparent.subject_type = parent.actor_type
          AND    grandparent.subject_id   = parent.actor_id
          WHERE  grandparent.actor_id     = :actor_id
          AND    grandparent.actor_type   = 'User'
          AND    grandparent.subject_type IN (:valid_connectors)
          AND    grandparent.priority     <= :direct
          AND    parent.actor_type        IN (:valid_connectors)
          AND    parent.subject_type      = 'Repository'
          AND    parent.priority          <= :direct
        SQL

        if require_a_minimum_ability_action?
          sql += Arel.sql "AND parent.action >= :min_action", min_action: Ability.actions[min_action]
        end

        ids = if use_db_repository_filter?(repository_ids: repository_ids)
          repository_ids.uniq.in_groups_of(BATCH_THRESHOLD, false).flat_map do |batch|
            batch_sql = sql + Arel.sql("AND parent.subject_id IN (:repository_ids)", repository_ids: batch)
            Ability.connection.select_values(batch_sql)
          end
        else
          Ability.connection.select_values(sql)
        end

        if organization
          org_repo_scope = organization.repositories.active
          if ids.size <= BATCH_THRESHOLD
            org_repo_scope.where(id: ids).pluck(:id)
          else
            ids.sort.each_slice(10_000).flat_map do |granted_ids|
              range = Range.new(granted_ids.first, granted_ids.last)
              scope = org_repo_scope.where(id: range)
              scope = scope.private_scope if exclude_public_repos?
              scope.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id")) & granted_ids
            end
          end
        else
          ids
        end
      end
    end

    # returns all the orgs for which the user has been granted an all_repo_role grant
    # the user can get this grant directly or through a team
    # the result can be scoped to
    # - a list of repos
    # - an org
    #
    # 1. get all the orgs for which the user has been granted an all_repo_role grant
    # 2. get all the teams the user is part of
    # 2a  - optionally limited to a a specific org or the owners of the repo list
    # 3. get all the teams that have been granted an all_repo_role grant
    # 4. combine orgs from 1 and 3
    # 5. get all repos of those orgs - outside of the experiment
    def org_ids_with_all_repo_role_grant_experiment(filter_repos, repository_ids)
      # In some tests the user is an organization here
      # We only want to calcualte the repo IDs for users
      return [] unless user.user?
      # if the organization is set, it takes presedence over any provider repo ids
      repo_orgs = if filter_repos && !organization
        fetch_associated_organization_ids(repository_ids)
      else
        []
      end

      if require_a_minimum_ability_action?
        fgp = Repository::AbilityDependency::ABILITY_TO_ALL_REPO_FGP[min_action]
      else
        # default to the lowest action/fgp if none is provided
        fgp = Repository::AbilityDependency::ABILITY_TO_ALL_REPO_FGP[:read]
      end

      # fetch orgs for which the user has been granted a role with the base FGP
      direct_scope = UserRole
      .where(actor_id: user.id, actor_type: "User", target_type: "Organization")
      .joins(:role)
      .joins(<<~SQL)
        JOIN role_permissions ON roles.base_role_id = role_permissions.role_id
      SQL
      .where("role_permissions.action = :fgp", fgp: fgp)

      # scope to a specific org if specified
      direct_scope = direct_scope.where(target_id: organization.id) if organization.present?

      # if list of repos was provided, scope to the repos' owning orgs
      # if org and repos were provided, the org takes precedence
      direct_scope = direct_scope.batched_scope(:target_id, values: repo_orgs) if !repo_orgs.empty?
      org_ids = direct_scope.pluck(:target_id).uniq

      # if we have orgs to filter on, we can return early if the orgs are already in the direct scope
      return org_ids if organization.present? && org_ids.include?(organization.id)
      return org_ids if !repo_orgs.empty? && org_ids.include?(repo_orgs)

      # For Indirect Assignments, we need to find all the teams a user is part of
      # getting all teams that are available to the user
      #
      # Note: in the control we are querying Abilities directly to get all the teams
      # if an organization is provided, the control adds a list of all teams the org ownes into an IN clause
      # which leads to Query too large errors in production - some orgs have over 15_000 teams
      # This function is using an `Platform::Loaders::UserTeams` loader, to be able to query for the org directly.
      teams_scope = user.teams(with_ancestors: true)
      # restrict the teams to the filter orgs
      teams_scope = teams_scope.where(organization_id: organization.id) if organization.present?
      team_ids = teams_scope.pluck(:id)

      unless team_ids.empty?
        indirect_scope = UserRole
        .where(actor_type: "Team", target_type: "Organization")
        .joins(:role)
        .joins(<<~SQL)
          JOIN role_permissions ON roles.base_role_id = role_permissions.role_id
        SQL
        .where("role_permissions.action = :fgp", fgp: fgp)

        indirect_scope = indirect_scope.where(target_id: organization.id) if organization.present?
        indirect_ids = indirect_scope.batched_scope(:actor_id, values: team_ids).pluck(:target_id)
        org_ids = (org_ids + indirect_ids).uniq
      end
      org_ids
    end

    def org_ids_with_all_repo_role_grant_control(filter_repos, repository_ids)
      return [] if GitHub.flipper[:all_repo_grant_evaluate_only_users].enabled? && !user.user?
      if require_a_minimum_ability_action?
        fgp = Repository::AbilityDependency::ABILITY_TO_ALL_REPO_FGP[min_action]
      else
        # default to the lowest action/fgp if none is provided
        fgp = Repository::AbilityDependency::ABILITY_TO_ALL_REPO_FGP[:read]
      end

      # fetch orgs for which individual user has been granted role with repo base_role with read/write/admin FGP
      sql = Arel.sql <<~SQL, actor_id: user.ability_delegate.ability_id, fgp: fgp
        SELECT user_roles.target_id
        FROM user_roles
        JOIN roles ON user_roles.role_id = roles.id
        JOIN role_permissions ON roles.base_role_id = role_permissions.role_id
        WHERE user_roles.actor_id = :actor_id
        AND user_roles.actor_type = 'User'
        AND user_roles.target_type = 'Organization'
        AND role_permissions.action = :fgp
      SQL
      # scope to a specific org if specified
      sql += Arel.sql("AND user_roles.target_id = :org_id", org_id: organization.id) if organization

      # if list of repos provided, scope to the repos' owning orgs
      # n/a if org was specifically specified as that takes precedent
      if !organization && filter_repos
        repo_owning_org_ids = fetch_associated_organization_ids(repository_ids)
        return [] if repo_owning_org_ids.empty?
        sql += Arel.sql("AND user_roles.target_id IN (:org_ids)", org_ids: repo_owning_org_ids)
      end

      # Teams user is a member of, specific to Org if one is provided
      teams_scope = Ability.where(actor_id: user.id, actor_type: "User", subject_type: "Team")
      teams_scope = teams_scope.where(subject_id: organization.team_ids) if organization

      team_ids = teams_scope.pluck(:subject_id)
      # fetch orgs for which team has been granted role with repo base_role with read/write/admin FGP
      if !team_ids.empty?
        sql += Arel.sql <<~SQL, team_ids: team_ids, fgp: fgp
          UNION
          SELECT user_roles.target_id
          FROM user_roles
          JOIN roles ON user_roles.role_id = roles.id
          JOIN role_permissions ON roles.base_role_id = role_permissions.role_id
          WHERE user_roles.actor_id IN (:team_ids)
          AND user_roles.actor_type = 'Team'
          AND user_roles.target_type = 'Organization'
          AND role_permissions.action = :fgp
        SQL

        # scope to a specific org if specified
        sql += Arel.sql("AND user_roles.target_id = :org_id", org_id: organization.id) if organization
      end
      UserRole.connection.select_values(sql)
    end

    def repository_ids_with_all_repo_role_grant(repository_ids: nil)
      return [] unless include_repositories_with_indirect_via_all_repo_role?

      repository_ids ||= @repository_ids
      filter_repos = repository_ids.present? && use_db_repository_filter?(repository_ids: repository_ids)

      org_ids = if GitHub.flipper[:repo_dependency_all_repo_grant_refactor].enabled?
        org_ids_with_all_repo_role_grant_experiment(filter_repos, repository_ids)
      else
        science "repo_dependency_all_repo_grant_batching" do |e|
          e.use do
            org_ids_with_all_repo_role_grant_control(filter_repos, repository_ids)
          end
          e.try do
            org_ids_with_all_repo_role_grant_experiment(filter_repos, repository_ids)
          end
          e.compare { |control, candidate| control.sort == candidate.sort }
        end
      end

      # select repos owned by that org
      scope = if exclude_public_repos?
        Repository.private_scope.active.org_owned.batched_scope(:organization_id, values: org_ids, batch_size: 10_000)
      else
        Repository.active.org_owned.batched_scope(:organization_id, values: org_ids, batch_size: 10_000)
      end

      if filter_repos
        scope.pluck(:id) & repository_ids
      else
        scope.pluck(:id)
      end
    end

    def is_business_teams_enabled_for_user?(user)
      return GitHub.flipper[:enterprise_teams_crud].enabled? if user.business_id <= 0
      Business.find_by(id: user.business_id)&.feature_enabled?(:enterprise_teams_crud)
    end

    # Fetches repository IDs for the user's business teams
    # Only checks if repository_ids are provided or an organization is provided
    def repository_ids_with_business_team_grant(repository_ids: nil)
      return [] unless include_repositories_with_indirect_via_business_team_org_association?
      return [] unless user.user?
      return [] unless is_business_teams_enabled_for_user?(user)

      repository_ids ||= @repository_ids

      # Check for specific organization
      if organization.present?
        repository_ids_for_organization_through_business_team(organization, repository_ids)
      else
        # fetch org ids for business teams related to user
        biz_team_org_ids = Orgs.domain.teams.business_team_org_ids_for_user(user_id: user.id, min_action: min_action)

        Repositories.domain.repo_ids_by_owners(
          owner_ids: biz_team_org_ids,
          ## if this is nil, we return all repo for owner ids
          ## if this is empty, we return empty array
          include_repo_ids: repository_ids,
          active_only: true
        )
      end
    end

    # Fetch a list of repository ids for the organization if the user has default access through business team membership
    def repository_ids_for_organization_through_business_team(org, repository_ids)
      return [] if !org.is_a?(Organization)
      # Determine minimum required ability action
      min_action_rank = Ability::ACTION_RANKING[min_action || :read]
      default_permission_rank = Ability::ACTION_RANKING[org.default_repository_permission.to_sym || :read]
      # Early return if the organization's default permission is below the minimum action
      return [] if default_permission_rank && default_permission_rank < min_action_rank
      business_team_ids = Orgs.domain.teams.business_team_ids_with_assigned_orgs_for(user_id: user.id, organization_id: organization.id)
      if business_team_ids.empty?
        []
      else
        repo_ids = Repositories.domain.repo_ids_by_owner(
          owner_id: org.id,
          repo_ids_in: repository_ids,
          active_only: true,
          public_only: false
        )
        repo_ids
      end
    end

    # Fetch organizations to filter based on the provided repository IDs
    def fetch_associated_organization_ids(repository_ids)
      return [] if repository_ids.nil? || repository_ids.empty?
      Repository.distinct.where(id: repository_ids).pluck(:organization_id)
    end

    def repository_ids_owned_by_user(repository_ids: nil)
      return [] if organization && organization != user

      repository_ids ||= @repository_ids

      sql = Arel.sql <<~SQL, user_id: user.id
        SELECT /*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id
        FROM repositories
        WHERE owner_id = :user_id
        AND active = 1
      SQL

      if use_db_repository_filter?(repository_ids: repository_ids)
        sql += Arel.sql "AND id IN (:repository_ids)", repository_ids: repository_ids
      end

      Repository.connection.select_values(sql)
    end

    # Public: Returns a list of repository ids which are roots or forks in networks
    # where the network root's owner is an org for which this user is an admin, and the network has at least one fork.
    #
    # For a repo to be included:
    # - the repo must be in a network which has forks
    # - the repo must have an organization_id that references an existing org
    # - the "plan_owner" (ie owner of the repo's network root) must be an org
    # - this user must be an admin of the network root's owning org
    # - the network root must be private
    def repository_ids_for_org_owned_private_repos_and_forks(repository_ids: nil)
      return [] if GitHub.flipper[:bypass_oopfs_query].enabled?(user) # rubocop:disable GitHub/UseActorFeatureEnabled

      ability_scope = Ability.user_admin_on_organizations(actor_id: user.id)
      ability_scope = ability_scope.where.not(subject_id: organization.id) if organization
      adminned_org_ids = ability_scope.pluck(:subject_id)
      return [] if adminned_org_ids.empty?

      if !organization
        adminned_org_ids = filter_orgs_with_oopfs_bypass(adminned_org_ids)
      end

      sql = Arel.sql <<~SQL, organization_ids: adminned_org_ids
        source_id IN (
          SELECT network_id
          FROM org_owned_private_networks_with_forks
          WHERE owner_id IN (:organization_ids)
          AND active = 1
        )
      SQL
      if use_db_repository_filter?(repository_ids: repository_ids)
        sql += Arel.sql "AND `repositories`.`id` IN (:repository_ids)", repository_ids: repository_ids
      end
      if organization
        sql += Arel.sql "AND owner_id = :organization_id", organization_id: organization.id
      end

      Repository.where(sql).pluck(:id)
    end

    # For orgs that we know do not use OOPFS (e.g. me50) we can remove them from the OOPFS query to speed it up
    def filter_orgs_with_oopfs_bypass(org_ids)
      return org_ids unless GitHub.flipper[:bypass_oopfs_query_org_killswitch].enabled?

      GitHub.dogstats.distribution_time("associated_repository_ids.oopfs_bypass") do
        org_ids.reject { |org_id| GitHub.flipper[:bypass_oopfs_query_org].enabled?(AdminnedOrgIdActor.new(org_id)) } # rubocop:disable GitHub/UseActorFeatureEnabled
      end
    end

    def require_a_minimum_ability_action?
      !@min_action.nil?
    end

    def include_repositories_owned_by_user?
      including.include?(:owned)
    end

    def include_repositories_with_direct_grants?
      including.include?(:direct)
    end

    def include_repositories_with_indirect_grants?
      include_repositories_with_indirect_via_adminship? || include_repositories_with_indirect_via_membership?
    end

    def include_repositories_with_indirect_via_adminship?
      # all indirects or just via adminship to org
      including.include?(:indirect) || including.include?(:indirect_via_adminship)
    end

    def include_repositories_with_indirect_via_membership?
      # all indirects or just via membership to org
      including.include?(:indirect) || including.include?(:indirect_via_membership)
    end

    def include_repositories_with_indirect_via_all_repo_role?
      # all indirects or just via all repo roles
      including.include?(:indirect) || including.include?(:indirect_via_all_repo_role)
    end

    def include_repositories_with_indirect_via_business_team_org_association?
      # all indirects or just via business_team
      including.include?(:indirect) || including.include?(:indirect_via_business_team_org_association)
    end

    def include_indirect_forks?
      @include_indirect_forks
    end

    # Include org-owned forks of private org repos where the user has admin
    # on the root organization? This matches pullable_by permissions checks.
    def include_org_owned_forks_of_private_org_owned_repos?
      return false unless @include_oopfs

      # We can bypass this under certain conditions if we're scoping the lookup
      # to a specific organization.
      if organization
        # If this org has no private forks, no need to check for source owners.
        return false unless organization.repositories.forks.private_scope.exists?

        # If the user is an admin and we're including indirect forks, they'll have
        # access that way.
        return false if organization.adminable_by?(user) && include_indirect_forks?
      end

      include_repositories_with_indirect_grants? &&
        include_indirect_forks? &&
        (!require_a_minimum_ability_action? || min_action == :read)
    end

    # Will the query return no results? This can happen if the includes option
    # is explicitly an empty array.
    def nothing_to_select?
      !(include_repositories_with_direct_grants? || include_repositories_with_indirect_grants?) &&
      !include_repositories_with_indirect_grants? &&
      !include_repositories_owned_by_user? &&
      !include_org_owned_forks_of_private_org_owned_repos?
    end

    def validate_min_action(value)
      return unless value

      unless Ability.actions.include?(value)
        raise ArgumentError, "Invalid min_action: #{min_action}"
      end
    end

    def validate_including(values)
      invalid_values = values - VALID_INCLUDING_VALUES
      if invalid_values.any?
        raise ArgumentError, "Invalid including values: #{invalid_values}"
      end
    end
  end
end
