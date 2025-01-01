# typed: true
# frozen_string_literal: true

# Adds organization-specific functionality to repositories, specifically
# permissions. A repository may be owned by a user or owned by an
# organization. In the latter case, the repository may belong to
# teams and accessed in various ways by an arbitrary number of
# users. This module handles that.
module Repository::OrganizationsDependency
  include GitHub::BatchMethod
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))
    belongs_to :organization

    scope :excluding_organization_ids, ->(organization_ids) {
      where.not(organization_id: organization_ids).or(where(organization_id: nil))
    }

    # Public: Asynchronously check if owning organization's billing Plan has seat-based pricing
    #
    # Preload the Organization's Business to avoid N+1s in the `plan.per_seat?` call for Organizations that
    # delegate pricing to a Business
    #
    # Returns a Hash of { Repository => Boolean }
    batch_method :owner_on_per_seat_plan? do |repos|
      GitHub::PrefillAssociations.prefill_associations(repos, :owner)
      GitHub::PrefillAssociations.prefill_batch_method(repos.map(&:owner), :async_business)
      repos.index_with do |repo|
        owner = repo.owner
        owner.organization? && owner.plan.per_seat?
      end
    end
  end

  # Does this repository belong to an Organization?
  #
  # Returns a Boolean
  def in_organization?
    !!(organization_id && organization)
  end

  def async_in_organization?
    return Promise.resolve(false) unless organization_id?

    async_organization.then do |organization|
      organization.present?
    end
  end

  def set_organization
    if owner&.organization?
      self.organization = T.cast(owner, Organization)
    elsif private? && T.cast(parent, T.nilable(Repository))&.in_organization? # rubocop:todo GitHub/AvoidCast
      self.organization = T.cast(T.must(parent), Repository).organization # rubocop:todo GitHub/AvoidCast
    else
      self.organization = nil
    end
  end

  # Internal: update this repository's organization and clean up
  # any collaboration permissions that no longer apply.
  #
  # inline_fork_cleanup: -  (optional, default false) whether inaccessible
  #                         fork cleanup should happen inline rather than via a
  #                         background job, if the organization has changed from
  #                         one to another.
  # remove_collaborators: - (optional, default true) if bringing a user-owned
  #                         repo into an organization, whether or not to remove
  #                         all direct repo collaborators. Set to false by
  #                         user->org transformation so members are preserved
  #                         temporarily. This option is only respected when
  #                         moving from user-owned to organization-owned.
  def update_organization(inline_fork_cleanup: false, remove_collaborators: true)
    old_org = organization
    set_organization
    save

    return if old_org == organization

    # Add this repo as a dependent of the new organization so adminable_by
    # checks &c succeed before the repo is removed from the former organization.
    T.must(organization).dependent_added(self) if organization

    if old_org
      old_org.dependent_removed(self)

      teams.owned_by(old_org).each do |team|
        team.remove_repository(self, inline_fork_cleanup: inline_fork_cleanup)
      end
    end

    remove_all_members if remove_collaborators && (old_org || organization)
  end

  # Can a user or team view or pull this repo?
  def pullable_by?(actor)
    resources.contents.readable_by?(actor)
  end

  def async_pullable_by?(actor)
    resources.contents.async_readable_by?(actor)
  end

  # Can a user link issues and PRs in this repo?
  def issues_and_prs_linkable_by?(actor)
    return false if locked?

    pushable_by?(actor)
  end

  def async_issues_and_prs_linkable_by?(actor)
    return Promise.resolve(false) if locked?

    async_pushable_by?(actor)
  end

  # Can the given actor push to this repo?
  # Checks the repo is writable and the user has permission
  #
  # actor - User
  # ref (optional) - String ref name
  #
  # Returns Boolean
  #
  # TODO: Call `async_pushable_by?().sync` (and fix the breaking tests) instead of duplicating this logic.
  def pushable_by?(actor, ref: nil)
    return false unless writable?
    return true if resources.contents.writable_by?(actor)

    if fork? && ref
      return ref_pushable_by?(actor: actor, ref: ref)
    end
    false
  end

  def has_maintain_role?(actor)
    direct_role_for(actor) == :maintain
  end

  def has_triage_role?(actor)
    direct_role_for(actor) == :triage
  end

  # Checks the user has permission to write to this repo.
  # Does not check if the repo itself is writable
  def authorized_to_write?(actor, ref: nil)
    return true if async_authorized_to_write?(actor).sync

    # the `PullRequest.find_open_based_on_head_ref` loop caters for the user
    # gaining collab permissions through a PR coming into the parent.
    if fork? && ref
      return ref_pushable_by?(actor: actor, ref: ref)
    end
    false
  end

  def async_pushable_by?(user)
    Promise.all([
      async_writable?,
      async_authorized_to_write?(user)
      ]).then do |repo_writable, user_authed|
      repo_writable && user_authed
    end
  end

  # TODO: Add fork-collab check to sync behavior of `async_authorized_to_write?` and `authorized_to_write?`.
  #       Then make `authorized_to_write?` call `async_authorized_to_write?`
  def async_authorized_to_write?(user)
    load_actor = if user&.respond_to?(:async_load_granular_actor_for)
      user.async_load_granular_actor_for(self)
    else
      Promise.resolve(user)
    end
    load_actor.then do
      next false unless user&.ability_delegate
      resources.contents.async_writable_by?(user)
    end
  end

  def async_user_relationship(user)
    return Promise.resolve(:none) unless user

    @async_user_relationships ||= {}
    @async_user_relationships[user.id] ||= async_adminable_by?(user).then do |adminable|
      next :owner if adminable

      async_contributor?(user).then do |contributor|
        next :contributor if contributor

        async_writable_by?(user).then do |writable|
          writable ? :collaborator : :none
        end
      end
    end
  end

  # Internal: Repository and Organization-level checks for whether a User can report
  #           an AbuseReportable record.
  #
  # This is used in AbuseReportable#async_viewer_can_report?. It's implemented at the
  # Repository level so that multiple comments on a timeline can share the memoized
  # check results here.
  #
  # See https://github.com/github/ce-community-and-safety/issues/1338#issuecomment-548590108
  # for decision tree on who can report in what circumstances
  #
  # Returns a Promise<Boolean> or Promise<nil> if the result can't be determined at this level.
  def async_user_can_report?(user)
    return Promise.resolve(false) unless GitHub.can_report?
    return Promise.resolve(false) unless user
    return Promise.resolve(false) if private?

    @async_user_can_report ||= {}
    @async_user_can_report[user.id] ||= async_writable_by?(user).then do |user_can_write|
      next true if user_can_write
      async_member?(user).then do |collaborator|
        next true if collaborator
        async_owner.then do |owner|
          next false unless owner
          (owner.organization? ? T.cast(owner, Organization).async_member?(user) : Promise.resolve(false)).then do |org_member|
            next true if org_member
            owner.async_blocking?(user).then do |user_blocked_by_owner|
              next false if user_blocked_by_owner
              nil
            end
          end
        end
      end
    end
  end

  # Public: Add the specified organization as a direct member of this
  # repository. This grants access to all members of the organization.
  #
  # organization - Organization to add to the repository.
  # action       - Level of access to grant.
  #
  # Returns nothing.
  def add_organization(org, action:)
    raise ArgumentError if org.nil?
    raise ArgumentError unless org.organization?
    return unless receives_organization_default_repository_permission?

    grant(org, action)
  end

  # Public: Remove the specified organization from this repository's direct
  # members. This removes the default permission from all members of the
  # organization.
  #
  # organization - Organization to remove from the repository.
  #
  # Returns nothing.
  def remove_organization(org)
    raise ArgumentError if org.nil?
    raise ArgumentError unless org.organization?
    return unless receives_organization_default_repository_permission?

    revoke(org)
  end

  # A Team scope representing the teams this repository is associated with.
  #
  # immediate_only - returns just the parent teams or includes all nested teams aswell
  def teams(immediate_only: true, include_all_repo_roles: false)
    async_teams(immediate_only: immediate_only, include_all_repo_roles: include_all_repo_roles).sync
  end

  # Public: Returns a Promise that resolves as a Team relation for this
  # Repository's teams.
  def async_teams(immediate_only: true, include_all_repo_roles: false)
    Platform::Loaders::RepositoryTeams.load(self, immediate_only: immediate_only).then do |team_ids|
      # include_all_repo_roles: include teams that have access via all repo roles (default to false)
      if include_all_repo_roles
        direct_all_repo_grants = self.all_repo_role_grants(:write)
        team_ids += T.must(direct_all_repo_grants["Team"]) if direct_all_repo_grants.key?("Team")
      end
      next Team.none unless team_ids.any?
      Team.where(id: team_ids)
    end
  end

  # A Scope of Teams the user belongs to which have access to this repository.
  # include_all_repo_roles: include teams that have access via all repo roles (default to false)
  def teams_for(user, include_all_repo_roles = false)
    return Team.none if !in_organization?
    user.teams.where(id: actor_ids_for_team_on_repo(include_all_repo_roles: include_all_repo_roles))
  end

  # A Scope of Teams the user is allowed to see which have access to this repository.
  # include_all_repo_roles: include teams that have access via all repo roles (default to false)
  def visible_teams_for(user, include_all_repo_roles = false)
    return Team.none if !in_organization?

    if user.respond_to?(:installation) &&
      resources.administration.readable_by?(user) &&
      !organization&.repository_resources.administration.readable_by?(user)
      teams.with_minimum_privacy(:closed).where(id: actor_ids_for_team_on_repo(include_all_repo_roles: include_all_repo_roles))
    else
      if organization&.business&.feature_enabled?(:enterprise_teams_crud)
        organization&.visible_teams_for(user, with_business_teams: true).where(id: actor_ids_for_team_on_repo(include_all_repo_roles: include_all_repo_roles))
      else
        organization&.visible_teams_for(user).where(id: actor_ids_for_team_on_repo(include_all_repo_roles: include_all_repo_roles))
      end
    end
  end

  def actor_ids_for_team_on_repo(action: nil, actor_ids: nil, min_action: nil, include_all_repo_roles: false)
    raise ArgumentError, "Cannot specify both action and min_action" if action && min_action

    all_repo_team_ids = []
    # only consider all repo role grants if requested and filtering on a particular role is not requested
    if include_all_repo_roles && action.nil?
      min_action = :read if min_action.nil?
      all_repo_team_ids = self.all_repo_role_grants(min_action).fetch("Team", [])
      if actor_ids
        all_repo_team_ids = all_repo_team_ids & actor_ids
      end
    end

    if self.owner&.business&.feature_enabled?(:enterprise_teams_crud)
      team_scope = Ability.teams_direct_on_repos(repo_id: id, include_business_teams: true)
    else
      team_scope = Ability.teams_direct_on_repos(repo_id: id)
    end

    if min_action
      raise ArgumentError, "'#{min_action}' is not a valid value for min_action" unless Ability.actions.key?(min_action)

      team_scope = team_scope.where("action >= ?", Ability.actions[min_action])
    end

    roles_to_filter_out = nil
    ability_action = nil
    role = nil

    # Figure out if action is specified, and if it's a legacy Ability action or a pre-defined
    # fine grained permission role
    if action.present?
      if ::Ability.actions[action]
        ability_action = action
      elsif Role.valid_system_role?(action)
        role = Role.preset_by_name(action)
      else
        role = RepositoryRole.custom_role_by_name(action, owner: owner)
      end

      # :read, :triage, :write & :maintain need to filter out any dependent custom roles
      base_role = role || Role.preset_by_name(ability_action)
      if base_role
        # a triage role has an underlying read ability
        # so for a query role:read we need to query for both roles based on read and on triage
        system_role_based_on_base_role = Role::BASE_ACTION_FOR_ROLE[base_role.name.to_sym]
        system_role = Role.preset_by_name(system_role_based_on_base_role)
        # All repo roles don't have an ability grant and don't need to be filtered out
        roles_to_filter_out = RepositoryRole.where(base_role: [base_role, system_role])
      end

      # If neither ability_action and role are defined, a valid action or role wasn't provided
      unless ability_action || role
        raise ArgumentError, "Invalid action for Repository#actor_ids_for_team_on_repo"
      end
    end

    # A Role was specified (triage, maintain or custom role). This can be determined solely from the
    # UserRole table. In this case we can shortcut and return quickly.
    if role
      if self.owner&.business&.feature_enabled?(:enterprise_teams_crud)
        role_team_ids = UserRole.where(role: role, target: self, actor_type: %w(Team BusinessTeam))
      else
        role_team_ids = UserRole.where(role: role, target: self, actor_type: "Team")
      end
      # if actor_ids is specified, we only need the intersection of role_team_ids and actor_ids
      role_team_ids = role_team_ids.where(actor_id: Array.wrap(actor_ids)) if actor_ids.present?
      return role_team_ids.pluck(:actor_id)
    end

    role_team_ids_to_remove = []

    if ability_action
      # Action filtering has some complications. Every Role has a "action" granted
      # in Abilties. So, when filtering on :read, we need to filter out Teams that are
      # also granted Triage.
      if self.owner&.business&.feature_enabled?(:enterprise_teams_crud)
        role_team_ids_to_remove = UserRole.where(role: roles_to_filter_out, target: self, actor_type: %w(Team BusinessTeam)).pluck(:actor_id)
      else
        role_team_ids_to_remove = UserRole.where(role: roles_to_filter_out, target: self, actor_type: "Team").pluck(:actor_id)
      end
      team_scope = team_scope.where(action: Ability.actions[ability_action])
    end

    if actor_ids
      team_scope = team_scope.where(actor_id: Array.wrap(actor_ids))
    end

    team_ids = team_scope.pluck(:actor_id) - role_team_ids_to_remove

    team_ids | all_repo_team_ids
  end

  # An Array of teams that the user is allowed to add this repository to.
  def addable_teams_for(user)
    return Team.none unless in_organization?
    return Team.none unless organization&.member?(user)
    return Team.none unless adminable_by?(user)
    return Team.none if access_group_setting&.deny_team_changes?

    organization&.visible_teams_for(user, with_business_teams: organization&.business&.feature_enabled?(:enterprise_teams_crud))
  end

  # Can this repository be added to the specified team by the specified user?
  #
  # team  - The Team we're checking addability for.
  # adder - The User trying to add this repo to a team.
  #
  # Returns a boolean.
  def can_add_to_team?(team, adder:)
    (addable_teams_for(adder) - teams).include?(team)
  end

  # All ids that are present in any of the teams the repository belongs to.
  #
  # include_org_admins - Boolean that indicates whether you'd like to include
  #                      all the owning org's admins (which always have access
  #                      to all org repos).
  #
  # Returns an Array of ids.
  def all_team_member_ids(include_org_admins:, immediate_only: true, min_action: nil, hide_private_org_owners: false, viewer: nil)
    return [] unless in_organization?

    team_ids = actor_ids_for_team_on_repo(min_action: min_action)

    if include_org_admins
      if organization&.member?(viewer) || !hide_private_org_owners
        Team.member_ids_of(team_ids, immediate_only: immediate_only) | organization&.admin_ids
      else
        public_member_ids = organization&.public_members&.pluck(:id)
        public_admin_ids = organization&.admins.where(id: public_member_ids).pluck(:id)
        Team.member_ids_of(team_ids, immediate_only: immediate_only) | public_admin_ids
      end
    else
      Team.member_ids_of(team_ids, immediate_only: immediate_only)
    end
  end

  # Public: The ids of any User with admin abilities on this repository
  def admin_ids
    PermissionCache.fetch ["admin_ids", id] do
      ids = actor_ids(type: "User", min_action: :admin)
      ids << owner_id if owner && !owner&.organization?
      ids
    end
  end

  # All users that are present in any of the teams the repository belongs to.
  #
  # include_org_admins - Boolean that indicates whether you'd like to include
  #                      all the owning org's admins (which always have access
  #                      to all org repos).
  #
  # Returns an Array of Users.
  def all_team_members(include_org_admins:)
    return User.none unless in_organization?
    PermissionCache.fetch ["all_team_members", ability_type, ability_id, include_org_admins] do
      User.where(id: all_team_member_ids(include_org_admins: include_org_admins))
    end
  end

  # Adds a repository to the team specified by `@team_for_after_create`
  # after creation.
  def add_repository_to_team
    if team = @team_for_after_create
      team.add_repository self, team.permission
    end
  end
  attr_accessor :team_for_after_create

  # Internal: Queue up a job to add teams of repository
  #
  # Used when a private organization repo is forked. In that case all teams
  # that have access to the parent will have access to the fork.
  #
  # repo - Repository to copy team permissions from
  #
  # Returns nothing
  def add_teams_of(repo)
    RepositoryAddTeamsJob.perform_later(id, repo.id)
  end

  # Internal: Add teams of repository
  #
  # repo      - Repository to copy team permissions from
  #
  # Returns nothing
  def add_teams_of!(repo)
    repo.teams.each do |team|
      Ability.throttle do
        team.add_repository(self, team.permission_for(repo))
      end
    end
  end

  # Public: Determine whether forking is enabled for this Repository or not.
  #
  # Returns true if forking this Repository is disabled.
  def forking_disabled?
    if in_organization? && private?
      return true unless allow_private_repository_forking?
    end

    false
  end

  # Find all of the child teams for the parent teams by combining infinite LIKE
  # statements. See full conversation around performance here: https://github.com/github/github/pull/74530
  #
  # teams - teams you want to find the children for
  #
  # Returns a list of child Teams (not including the parent teams)
  def child_teams(teams)
    return Team.none if teams.empty?

    Team.where(teams.map(&:tree_path).map { |path| "tree_path LIKE '#{path}/%'" }.join(" OR "))
  end

  private

  def ref_pushable_by?(actor:, ref:)
    pulls = PullRequest.find_open_based_on_head_ref(id, ref)

    fork_collab_granted_prs = pulls.select(&:fork_collab_granted?)
    GitHub::PrefillAssociations.prefill_associations(fork_collab_granted_prs, :base_repository,
      available_records: [self])

    pull = fork_collab_granted_prs.detect do |pr|
      base_repo = pr.base_repository
      next false unless base_repo.resources.contents.writable_by?(actor)

      # The fork_collab feature can only be set by the PR author and is intended to allow users with
      # read-only access to the head repo the ability to write to the head ref within the head repo.
      # In addition to making sure the actor has the correct permissions, we need to ensure the PR
      # author still has write access to the head repo in case they have since lost write access,
      # and thus lost the ability to grant write access to others.
      pr.head_repository.resources.contents.writable_by?(pr.user)
    end

    GitHub.dogstats.increment("authentication.fork_collab", tags: [pull != nil ? "result:granted" : "result:denied"])

    !pull.nil?
  end
end
