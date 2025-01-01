# typed: true
# frozen_string_literal: true

module Repository::AbilityDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  PRELOAD_BATCH_SIZE = 500
  VISIBLE_ASSIGNEES_BATCH_THRESHOLD = 400

  # This defines how an ability action maps to an all repo FGP
  ABILITY_TO_ALL_REPO_FGP = {
    read: "read_repo",
    write: "write_repo",
    admin: "admin_repo"
  }

  included do
    T.bind(self, T.class_of(Repository))

    # rubocop:todo GitHub/AvoidActiveRecordCallbacks
    after_create :add_members_with_default_repository_permissions, unless: :skip_after_create_callbacks?
    # rubocop:enable GitHub/AvoidActiveRecordCallbacks
  end

  module ClassMethods
    extend T::Helpers
    include Scientist


    requires_ancestor { Kernel }

    # Stores in the in-process PermissionCache each of the direct abilities
    # between a set of users and a set of repositories.
    def preload_repository_permissions(users:, repositories:)
      users = users&.compact
      return unless users && users.any? && users.all?(&:persisted?)

      user_ids = users.map(&:id)

      # Clear current values
      # This establishes a cache entry for every pair in the list. Later on,
      # pairs with abilities will be populated, but those without would result in a
      # cache miss if this step was not done.
      # See https://github.com/github/github/pull/69398/files#r103492483
      repositories.each do |repository|
        user_ids.each do |user_id|
          cache_key = repository_permission_cache_key(user_id, repository.id)
          PermissionCache.set(cache_key, nil)
        end
      end

      repositories.each_slice(PRELOAD_BATCH_SIZE) do |batch_repositories|
        abilities = Authorization.service.most_capable_abilities_between_multiple_actors_and_subjects(
          actor_type: User,
          actor_ids: user_ids,
          subject_type: Repository,
          subjects: batch_repositories,
        )

        # Set new values for each ability record
        abilities.each do |ability|
          cache_key = repository_permission_cache_key(ability.actor_id, ability.subject_id)
          PermissionCache.set(cache_key, ability)
        end
      end
    end

    def repository_permission_cache_key(user_id, repository_id)
      [
        Authorization::Queries::MostCapableAbilityBetween::MCAB_CACHE_PREFIX,
        "User",
        user_id,
        "Repository",
        repository_id
      ]
    end

    # Public: Converts a Repository permission to the equivalent Ability action.
    #
    # action - Symbol or String action (pull, triage, push, maintain, or admin).
    #
    # Returns an Ability action symbol. Raises ArgumentError if given an invalid (or custom) role.
    def permission_to_action(action)
      case Role.clean_action(action)
      when "read", "pull"
        :read
      when "triage"
        :triage
      when "write", "push"
        :write
      when "maintain"
        :maintain
      when "admin"
        :admin
      else
        raise ArgumentError, "Invalid permission passed: #{action}."
      end
    end

    # Public: get a hash of permissions from an actor's role on the repository.
    #
    # role - String or Symbol representing the role the actor has on the given repo.
    #        Does not support custom roles, role must be one of
    #        :read, :triage, :write, :maintain, :admin
    #
    # Returns: Hash of permissions
    #     => { pull: true, triage: true, push: true, maintain: true, admin: true }
    def permissions_hash(role)
      role = Role.clean_action(role)
      role = case role
      when "read", "write"   # permission_to_action only handles pull/push, but we can get calls with read/write here as well
        role.to_sym
      else
        begin
          permission_to_action(role)
        rescue ArgumentError
          nil
        end
      end

      role_fixnum = Ability::ACTION_RANKING[role] || -1

      {
        admin: (role_fixnum >= Ability::ACTION_RANKING[:admin]),
        maintain: (role_fixnum >= Ability::ACTION_RANKING[:maintain]),
        push: (role_fixnum >= Ability::ACTION_RANKING[:write]),
        triage: (role_fixnum >= Ability::ACTION_RANKING[:triage]),
        pull: (role_fixnum >= Ability::ACTION_RANKING[:read]),
      }
    end

    # Given a user and a set of repository id's,
    # return the repository ids the user has (admin) access to due to the fact that
    # they are an admin of the repo's owning organization
    #
    # Returns an Array of id's
    def accessible_via_org_admin(user, repo_ids, organization_id = nil)
      # create a map between repo id and owning org id
      if organization_id
        repo_to_org = Repository
          .where(id: repo_ids)
          .where(organization_id:)
          .pluck(:id, :organization_id)
          .to_h
      else
        repo_to_org = Repository
          .where(id: repo_ids)
          .where.not(organization_id: nil)
          .pluck(:id, :organization_id)
          .to_h
      end

      owning_organization_ids = repo_to_org.values
      return [] if owning_organization_ids.empty?

      # orgs the user admins that are owners of the repos provided
      repo_owning_orgs_user_admins = Ability.user_admin_on_organization(
        actor_id: user.id,
        subject_id: owning_organization_ids.uniq,
      ).pluck(:subject_id)

      return [] if repo_owning_orgs_user_admins.empty?

      repo_to_org.reduce([]) do |adminable_repo_ids, (repo_id, owning_org_id)|
        adminable_repo_ids << repo_id if repo_owning_orgs_user_admins.include?(owning_org_id)
        adminable_repo_ids
      end
    end

    # Determines the target for for conditional access for multiple Business instances
    #
    # repositories - an enumerable of Business
    #
    # returns Hash[Repository] => target for conditional access
    def multiple_target_for_conditional_access(repositories)
      ConditionalAccess::Filter.ensure_with_class(repositories, Repository)

      # This avoids a query when the TFCA is already loaded
      # We don't want to use promises here because we likely have promises syncing outside of this call
      # and this could cause a Promise::BrokenError exception (see https://github.com/github/issues/issues/2242)
      repos_with_owners_loaded, repos_with_owners_not_loaded = repositories.partition { |repo| repo.association(:owner).loaded? }
      GitHub::PrefillAssociations.prefill_associations(repos_with_owners_not_loaded, [:owner], available_records: repos_with_owners_loaded.map(&:owner))

      result = {}
      repositories.each do |repo|
        next if repo.owner.nil?
        result[repo] = repo.owner
      end

      result
    end

    def repo_ids_not_visible_to_user_from_orgs(user, organization_ids, repo_ids: [], include_archived_repos: true)
      all_orgs_private_repo_ids = Repositories.domain.repo_ids_by_org_ids(
        org_ids: organization_ids,
        include_repo_ids: repo_ids.empty? ? nil : repo_ids,
        private_only: true,
        exclude_archived: !include_archived_repos,
        active_only: false
      )

      user_associated_repository_ids = []
      all_orgs_private_repo_ids.each_slice(100).map do |group_ids|
        associated_ids = user.associated_repository_ids(repository_ids: group_ids)
        user_associated_repository_ids.concat(associated_ids).uniq!
      end

      # Load all internal repositories for the user. This is only to exclude internal repos
      # so it doesn't matter if we load Rando Business internal IDs when cleaning up a user from a non-associated org.
      user_associated_repository_ids |= user.internal_repositories.pluck(:id)

      all_orgs_private_repo_ids - user_associated_repository_ids
    end
  end

  mixes_in_class_methods(ClassMethods)

  def ability_description
    name_with_owner
  end

  def owning_organization_id
    original_owning_organization_id
  end

  def original_owning_organization_id
    # FORK SCENARIOS
    #
    # public repo is forked:
    # - org-owned repo --> user account - no org admins have access
    # - org-owned repo --> org account - fork's org admins have access
    #   - we need to use fork.owner_id instead of fork.organization_id
    #   - because if the fork's parent repo is transferred to another org
    #   - the parent repo's organization_id isn't updated
    #
    # private repo is forked:
    # org-owned repo --> user owner - parent repo org admins have access
    # org-owned repo --> org owner - new org admins have access
    # user-owned repo --> org owner - new org admins have access
    # user-owned repo --> user owner - n/a no orgs involved
    if fork?
      return if owner&.user? && parent&.public?
      return parent&.organization_id if owner&.user?
      return owner_id if owner&.organization?
    end
    # if it is not a fork at all,
    # we want to know the current repo's organization_id or owner.id
    # (which should be the same)
    if owner&.organization?
      # sometimes organization_id isn't populated after a user is transformed
      # to an organization for the repos they own
      organization_id || owner_id
    end
  end

  def async_owning_organization_id
    async_owner.then do |owner|
      # FORK SCENARIOS
      #
      # public repo is forked:
      # - org-owned repo --> user account - no org admins have access
      # - org-owned repo --> org account - fork's org admins have access
      #   - we need to use fork.owner_id instead of fork.organization_id
      #   - because if the fork's parent repo is transferred to another org
      #   - the parent repo's organization_id isn't updated
      #
      # private repo is forked:
      # org-owned repo --> user owner - parent repo org admins have access
      # org-owned repo --> org owner - new org admins have access
      # user-owned repo --> org owner - new org admins have access
      # user-owned repo --> user owner - n/a no orgs involved
      if fork?
        next owner_id if owner&.organization?

        async_parent.then do |parent|
          parent.organization_id if parent&.private?
        end
      else
        # if it is not a fork at all,
        # we want to know the current repo's organization_id or owner.id
        # (which should be the same)
        next unless owner&.organization?

        # sometimes organization_id isn't populated after a user is transformed
        # to an organization for the repos they own
        organization_id || owner.id
      end
    end
  end

  def owning_organization_type
    "Organization"
  end

  # Internal: Used by Abilities to ensure that only users or teams can be
  # granted abilities on a Repository.
  def grant?(actor, action)
    (actor.is_a?(User) || actor.is_a?(Team)) && super
  end

  # Internal: The minimum ability to grant to a new member.
  def baseline
    public? ? :write : :read
  end

  # Public: allow a team access to this repo.
  def add_team(team, action:)
    grant team, action
    Repository::AdvisoryAbilityManager.grant(team, repository: self, action: action)
    # Ensure we remove access to Protected Branches when team looses write access
    if action == :read
      ProtectedBranch::AbilityRepositoryManager.revoke(team, repository: self)
    end
  end

  # Public: remove access to this repo from a team.
  def remove_team(team)
    # Ensure we remove access to Vulnerability Alerts
    vulnerability_manager.revoke_user_or_team(team)
    revoke team
    Repository::AdvisoryAbilityManager.revoke(team, repository: self)
    # Ensure we remove access to Protected Branches
    ProtectedBranch::AbilityRepositoryManager.revoke(team, repository: self)
  end

  def readable_by?(actor, include_child_teams: false)
    if include_child_teams && actor.is_a?(Team)
      actor.direct_or_inherited_repo_ids.include?(id)
    else
      super(actor)
    end
  end

  def writable_by?(actor, include_child_teams: false)
    if include_child_teams && actor.is_a?(Team)
      actor.direct_or_inherited_repo_ids(action: [:write, :admin]).include?(id)
    else
      super(actor)
    end
  end

  def can_be_interacted_with_by?(actor, user_can_push: nil)
    if user_can_push.nil?
      user_can_push = pushable_by?(actor)
    end
    User::InteractionAbility.interaction_allowed?(user: actor, repository: self, user_can_push: user_can_push)
  end

  # Public: Repository's access control consults more than just abilities.
  #
  # actor  - a User or Team, though it's generally a User.
  # action - a :read, :write, or :admin Symbol
  #
  # Returns a Boolean
  def permit?(actor, action)
    GitHub.dogstats.time("repository", tags: ["action:permit"]) do
      async_permit?(actor, action).sync
    end
  end

  # Public: Repository's access control consults more than just abilities.
  #
  # actor  - a User or Team, though it's generally a User.
  # action - a :read, :write, or :admin Symbol
  #
  # Returns Promise<bool>
  def async_permit?(actor, action)
    actor = actor.ability_delegate

    return Promise.resolve(false) if unpersisted?
    return Promise.resolve(false) if actor&.ability_type == "Organization"

    # everything can read public repositories when private mode is disabled
    # an actor is always required when private mode is enabled
    return Promise.resolve(true) if public? && action == :read && (!GitHub.private_mode_enabled? || actor.present?)

    # an actor is required
    return Promise.resolve(false) if !actor

    # an actor is operating on something it owns
    return Promise.resolve(true) if actor&.ability_type == "User" && actor.id == owner_id

    chain = Promise.resolve
    if action == :read
      chain = chain.then do |value|
        next value if value
        # A user has access to an internal repository as a member of a business (this hits the DB)
        async_can_read_internal_repo_via_business_membership(actor)
      end
    end

    chain = chain.then do |value|
      next value if value

      # the actor's abilities allow it (this hits the DB), or
      super.then do |result|
        next true if result

        # the actor has unlocked the repo, or
        actor&.ability_type == "User" && actor.async_has_unlocked_repository?(self)
      end.then do |result|
        next true if result

        # public push is enabled on a public repo (Enterprise only), or
        next true if GitHub.public_push_enabled? && :write == action && public_push? && public?

        # the actor has access via an all-repo role
        async_has_all_repo_role_for?(actor, action).then do |has_all_repo_role|
          next true if has_all_repo_role

          # the actor is trying to read a fork of a private repo that's owned by
          # an org that the actor is an owner of
          actor&.ability_type == "User" && :read == action && async_owner_of_parent_org?(actor)
        end
      end
    end

    # Business team default org permissions check
    chain = chain.then do |value|
      next value if value
      async_fetch_business_team_permission_if_exists(actor).then do |default_permission|
        if default_permission.nil? || Ability::ACTION_RANKING[default_permission].nil?
          false
        else
          Ability::ACTION_RANKING[default_permission] >= Ability::ACTION_RANKING[action]
        end
      end.then do |result|
        result || false
      end
    end

    chain
  end

  def async_fetch_business_team_ids(actor)
    repository.async_business.then do |business|
      next nil if actor.nil? || business.nil?
      next nil unless business&.enterprise_teams_org_roles_supported?
      Orgs.domain.teams.business_team_ids_for(business_id: business&.id, user_id: actor.id)
    end
  end

  def async_fetch_business_team_permission_if_exists(actor)
    repository.async_business.then do |business|
      next nil unless is_business_team_enabled?(business)
      next nil unless owner.present? && owner&.organization? # loaded by async_business
      organization = T.cast(owner, Organization)
      actor_type = actor&.ability_type
      case actor_type
      when "User"
        # Check if the user is part of a business team that belongs to the organization
        team_permission = business.teams_for(actor).find do |team|
          team.organization_ids.include?(organization.id)
        end
        team_permission ? organization.default_repository_permission.to_sym : nil
      when "BusinessTeam"
        if actor.business_team? && actor.organization_ids.include?(organization.id)
          organization.default_repository_permission.to_sym
        end
      end
    end
  end

  private def is_business_team_enabled?(business)
    return false if business.nil?
    business.erp_feature_enabled?(:enterprise_teams_org_assignment)
  end

  private def async_has_all_repo_role_for?(actor, action)
    async_owner.then do |owner|
      # in_organization? is true for forks of org repos, while organization? is only true for directly-owned repos
      # todo - should all-repo roles apply to forks?
      # This needs to also be updated for permit? to return business team permissions
      next false unless owner&.organization?

      actor_type = actor&.ability_type
      action_sym = action.to_sym
      actor_id = Set.new([actor.id])

      PermissionCache.fetch ["repo_ability_dependency_all_repo_role_granted", actor_type, actor.id, action, owner.id] do
        case actor_type
        when "User"
          next true if all_repo_role_granted?("User", actor_id, action_sym)
          all_team_ids = T.let(Set.new, T::Set[Integer])
          T.cast(owner, Organization).teams_for(actor).each { |team| all_team_ids.merge(team.id_and_ancestor_ids) }

          async_fetch_business_team_ids(actor).then do |business_team_ids|
            if !business_team_ids.nil?
              actor_type_to_ids = {
                "Team" => all_team_ids.to_a,
                "BusinessTeam" => business_team_ids.to_a
              }

              all_team_ids.merge(business_team_ids)
              team_actors = %w(Team BusinessTeam)

              all_repo_role_granted_multiple_actor_types?(team_actors, all_team_ids, action_sym, actor_type_to_ids)
            else
              all_repo_role_granted?("Team", all_team_ids, action_sym)
            end
          end
        when "Team"
          all_repo_role_granted?("Team", Set.new(actor.id_and_ancestor_ids), action_sym)
        when "BusinessTeam"
          all_repo_role_granted?("BusinessTeam", actor_id, action_sym)
        else
          false
        end
      end
    end
  end

  sig do
    params(
      actor_type: String,
      actor_ids: T::Set[Integer],
      action: Symbol
    ).returns(T::Boolean)
  end
  # returns true if an all-repo role granting 'action' is assigned to any of the actors
  private def all_repo_role_granted?(actor_type, actor_ids, action)
    return false if actor_ids.empty?
    actor_type_to_ids = { actor_type => actor_ids.to_a }

    all_repo_role_granted_for_actors(actor_type_to_ids, action)
  end

  sig do
    params(
      actor_types_to_ids: T::Hash[String, T::Array[Integer]],
      action: Symbol
    ).returns(T::Boolean)
  end
  private def all_repo_role_granted_for_actors(actor_types_to_ids, action)
    Authz.domain.user_roles.repo_role_granted_to_any_actor?(
      target: T.cast(owner, Organization),
      actor_types_to_ids: actor_types_to_ids,
      permission: Authz::Domain::RepoPermissionType.ability_action_to_repo_permission(action)
    )
  end

  sig do
    params(
      actor_types: T::Array[String],
      actor_ids: T::Set[Integer],
      action: Symbol,
      actor_type_to_ids: T::Hash[String, T::Array[Integer]]
    ).returns(T::Boolean)
  end
  # returns true if an all-repo role granting 'action' is assigned to any of the actors
  private def all_repo_role_granted_multiple_actor_types?(actor_types, actor_ids, action, actor_type_to_ids)
    return false if actor_ids.empty?

    all_repo_role_granted_for_actors(actor_type_to_ids, action)
  end

  private def repo_role_from_action(action)
    repo_role = case action.to_sym
    when :read
      "read_repo"
    when :write
      "write_repo"
    when :admin
      "admin_repo"
    else
      raise ArgumentError, "Invalid action: #{action}"
    end
  end


  private def async_can_read_internal_repo_via_business_membership(actor)
    # A user has access to an internal repository as a member of a business (this hits the DB)
    # Internal repos can be read only if provisioned members hold a license
    async_internal_repository.then do |internal_repository|
      business_ids_promise = (actor&.ability_type == "User" && internal_repository) ? actor.async_business_ids(valid_license: true) : Promise.resolve([])

      business_ids_promise.then do |business_ids|
        internal_repository && business_ids.include?(internal_repository.business_id)
      end
    end
  end

  # Centralizes the logic used in Platform::Objects::Repository.async_viewer_can_see? so that
  # anyone can check permissions comprehensively on a repository loaded via an association to some
  # other object.
  #
  # See https://github.com/github/github/pull/109897/files#r265126550.
  #
  # Returns Promise<Boolean>.
  def async_visible_and_readable_by?(viewer)
    return Promise.resolve(true) if viewer&.site_admin? # Staff can read all metadata.

    return Promise.resolve(false) if access.disabled? # Don't show DMCA-takedown repos.
    return Promise.resolve(false) if access.tos_violation? || access.disabled_by_admin? # Don't show tos violated repos.

    Platform::Loaders::ActiveRecordAssociation.load(self, user_association_for_spammy).then do
      next false if hide_from_user?(viewer)

      resources.metadata.async_readable_by?(viewer).then do |readable|
        next true if readable
        next false unless viewer

        adminable_by?(viewer) || has_invitation_for?(viewer)
      end
    end
  end

  def visible_and_readable_by?(viewer)
    async_visible_and_readable_by?(viewer).sync
  end

  def async_access_level_for(actor, include_employee_granted_permissions: true)
    return Promise.resolve(nil) if unpersisted?
    return Promise.resolve(nil) if actor.is_a?(User) && !actor.user?

    if actor.nil? || actor.new_record?
      # no actor is required if it's public and private mode is disabled
      if public? && !GitHub.private_mode_enabled?
        return Promise.resolve(:read)
      else
        return Promise.resolve(nil)
      end
    end

    # an actor is operating on something it owns
    return Promise.resolve(:admin) if actor.class == User && actor.id == owner_id

    chain = Promise.resolve

    if actor.class == User && include_employee_granted_permissions
      chain = chain.then do |value|
        next value if value

        # the actor has unlocked the repo for admin access
        actor.async_has_unlocked_repository?(self).then do |has_unlocked_repository|
          :admin if has_unlocked_repository
        end
      end
    end

    chain = chain.then do |value|
      next value if value

      actions = Set.new

      # the actor's abilities allow it.
      # This hits the DB if there's no information in the permission cache
      # which is currently being populated by `self.preload_repository_permissions`
      action_promise = Authorization.service.async_most_capable_action_between(actor: actor, subject: self)
      action_promise.then do |action|
        actions << action.to_sym if action

        # public push is enabled on a public repo (Enterprise only)
        actions << :write if public_push?

        # public repos get read by default
        actions << :read if public?

        async_all_repo_role_allowed_actions(actor).then do |allowed_actions|
          allowed_actions.each do |action|
            actions << action
          end
        end

        # Check if the user is part of a business team that belongs to the organization
        async_fetch_business_team_permission_if_exists(actor).then do |default_permission|
          actions << default_permission unless default_permission.nil? || Ability::ACTION_RANKING[default_permission].nil?
        end

        # return the max level if present
        level = actions.max_by { |action| T.cast(Ability.actions[action], Integer) }
        next level if level

        async_owner_of_parent_org?(actor).then do |owner_of_parent_org|
          # the actor is trying to read a fork of a private repo that's owned by an
          # org that the actor is an owner of
          owner_of_parent_org ? :read : nil
        end
      end
    end

    chain = chain.then do |value|
      next value if value
      # A user has access to an internal repository as a member of a business (this hits the DB)
      async_can_read_internal_repo_via_business_membership(actor).then do |can_read|
        :read if can_read
      end
    end
  end

  private def async_all_repo_role_allowed_actions(actor)
    async_owner.then do |owner|
      # in_organization? is true for forks of org repos, while organization? is only true for directly-owned repos
      # todo - should all-repo roles apply to forks?
      next [] unless owner&.organization?

      actor_type = actor&.ability_type
      actor_id = Set.new([actor.id])
      PermissionCache.fetch ["repo_ability_dependency_async_all_repo_role_allowed_actions", actor_type, actor.id, owner.id] do
        case actor_type
        when "User"
          user_actions = all_repo_role_allowed_action_for_actor("User", actor_id)
          all_team_ids = Set.new
          T.cast(owner, Organization).teams_for(actor).each { |team| all_team_ids.merge(team.id_and_ancestor_ids) }

          business_team_ids = async_fetch_business_team_ids(actor).value
          if !business_team_ids.nil?
            actor_type_to_ids = {
              "Team" => all_team_ids.to_a,
              "BusinessTeam" => business_team_ids.to_a
            }

            all_team_ids.merge(business_team_ids)
            team_actors = %w(Team BusinessTeam)
            team_actions = all_repo_role_allowed_action_for_actors(team_actors, all_team_ids, actor_type_to_ids)
          else
            team_actions = all_repo_role_allowed_action_for_actor("Team", all_team_ids)
          end
          user_actions | team_actions
        when "Team"
          all_repo_role_allowed_action_for_actor("Team", Set.new(actor.id_and_ancestor_ids))
        when "BusinessTeam"
          all_repo_role_allowed_action_for_actor("BusinessTeam", Set.new(actor.id_and_ancestor_ids))
        else
          []
        end
      end
    end
  end

  sig do
    params(
      actor_types_to_ids: T::Hash[String, T::Array[Integer]]
    ).returns(T::Array[Symbol])
  end
  private def all_repo_role_allowed_action_for_actors_list(actor_types_to_ids)
    Authz.domain.user_roles.ability_actions_for_target_and_actors(
      target: T.cast(owner, Organization),
      actor_types_to_ids: actor_types_to_ids
    )
  end

  sig do
    params(
      actor_type: String,
      actor_ids: T::Set[Integer]
    ).returns(T::Array[Symbol])
  end
  private def all_repo_role_allowed_action_for_actor(actor_type, actor_ids)
    return [] if actor_ids.empty?

    actor_type_to_ids = { actor_type => actor_ids }

    all_repo_role_allowed_action_for_actors_list(actor_type_to_ids)
  end

  sig do
    params(
      actor_types: T::Array[String],
      actor_ids: T::Set[Integer],
      actor_types_to_ids: T::Hash[String, T::Array[Integer]]
    ).returns(T::Array[Symbol])
  end
  private def all_repo_role_allowed_action_for_actors(actor_types, actor_ids, actor_types_to_ids)
    return [] if actor_ids.empty?

    all_repo_role_allowed_action_for_actors_list(actor_types_to_ids)
  end

  def cached_async_adminable_by?(user)
    @async_adminable_by_cache ||= {}
    @async_adminable_by_cache[user&.id] ||= async_adminable_by?(user)
  end

  def access_level_for(actor)
    async_access_level_for(actor).sync
  end

  def role_based_access_level(actor, include_custom_roles: false)
    async_action_or_role_level_for(actor, include_custom_roles: include_custom_roles).sync
  end

  # Public: calculate the direct role for the actor on the repository.
  # The role can be any of :read, :triage, :write, :maintain, :admin.
  #
  # Returns a Symbol or nil
  def direct_role_for(actor)
    direct_roles_for([actor], actor_type: actor.ability_type)[actor]
  end

  # Public: calculate the direct roles for the given actors on the repository.
  # The role can be any of :read, :triage, :write, :maintain, :admin.
  # If the actor doesn't have direct role over the repo, it won't be part of the result Hash.
  #
  # - actors: Enumerable of objects.
  # - actor_type: the type of the input actors. Must be a valid Ability.actor_type.
  #
  # Returns a Hash{actor => Symbol}
  def direct_roles_for(actors, actor_type: "Team")
    return {} if actors.blank?

    actors = actors.select { |actor| !actor.is_a?(User) || actor.user? }
    actor_ids = actors.map(&:ability_id)

    action_by_actor_id = Ability.where(
      actor_id: actor_ids,
      actor_type: actor_type,
      subject_id: self.id,
      subject_type: "Repository",
      priority: Ability.priorities[:direct],
    ).pluck(:actor_id, :action).each_with_object({}) do |(actor_id, action), result|
      result[actor_id] = action.to_sym
    end

    actors_roles = UserRole.where(
      actor_id: actor_ids,
      actor_type: actor_type,
      target_id: self.id,
      target_type: "Repository",
    ).index_by(&:actor_id)

    actors.each_with_object({}) do |actor, result|
      action = action_by_actor_id[actor.id]
      next if action.nil?

      ability_rank = Ability::ACTION_RANKING[action]

      actor_role = actors_roles[actor.id]
      if actor_role.nil?
        result[actor] = action
        next
      end

      role = actor_role.role

      # A custom repository role will always take priority over a system role
      if role.custom? || role.action_rank > ability_rank
        result[actor] = role.name.to_sym
      else
        result[actor] = action
      end
    end
  end

  # Public: translates Ability action to repo fine grained permission
  # action: Ability.action (:read, :write, :admin) with a default of :read
  def action_to_repo_fgp(action = :read)
    begin
      fgp = Ability::ALL_REPO_ROLE_FGP_ABILITY.invert.fetch(action.to_sym)
    rescue KeyError
      raise ArgumentError, "Invalid action: #{action}"
    end
  end

  # Public: enumerates the list of actors with direct all repo role grants on the repository.
  # min_action: the minimum action to consider. Must be a valid Ability.action (:read, :write, :admin) with a default of :read
  # Returns a hash with the actor type as a key (User, Team, BusinessTeam) and an array of the actor ids with sufficient access as value.
  sig { params(min_action: T.nilable(Symbol)).returns(T::Hash[String, T::Array[Integer]]) }
  def all_repo_role_grants(min_action = :read)
    return {} unless owner && owner&.organization?
    min_action = :read if min_action.nil?
    min_fgp = action_to_repo_fgp(min_action)

    params = {
      target_type: "Organization",
      target_id: owner_id,
      target: owner,
      min_fgp: min_fgp
    }

    Authz.domain.user_roles.batch_role_assignments_with_base_role_for_target(
     target: params[:target],
     permission: Authz::Domain::RepoPermissionType.from_string(params[:min_fgp])
   )
  end

  def user_ids_with_all_repo_role_grants(min_action: :read, include_child_teams: true)
    user_ids = []
    direct_all_repo_grants = all_repo_role_grants(min_action)
    return user_ids if direct_all_repo_grants.empty?

    # add users directly granted all repo role
    user_ids += T.must(direct_all_repo_grants["User"]) if direct_all_repo_grants.key?("User")

    # Add team members indirectly assigned all repo role
    if direct_all_repo_grants.key?("Team")
      user_ids += Team.member_ids_of(T.must(direct_all_repo_grants["Team"]), immediate_only: !include_child_teams)
    end

    if owner&.business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
      # Add business team members indirectly assigned all repo role
      if direct_all_repo_grants.key?("BusinessTeam")
        # NOTE(assyadh): business teams do not support nested teams yet.
        user_ids += Orgs.domain.teams.user_ids_for_business_teams(T.must(direct_all_repo_grants["BusinessTeam"]))
      end
    end

    user_ids.uniq
  end

  # Public: get a hash of permissions for the given actor on the repository.
  #
  # actor - user or team to get permissions for
  #
  # Returns: Hash of permissions
  #     => { pull: true, triage: true, push: true, maintain: true, admin: true }
  def permissions_hash_for(actor:)
    role = case actor
    when User
      role_based_access_level(actor)
    when Team
      actor.async_most_capable_action_or_role_for(self).sync
    else
      raise ArgumentError
    end

    Repository.permissions_hash(role)
  end

  # Public: Is the specified user an owner of the parent repo's owning
  # organization?
  #
  # actor - User to check org ownership of.
  #
  # Returns a boolean
  def owner_of_parent_org?(actor)
    in_organization? && plan_owner&.organization? && plan_owner&.adminable_by?(actor)
  end

  def async_owner_of_parent_org?(actor)
    async_in_organization?.then do |in_organization|
      next false unless in_organization
      async_plan_owner.then do |block_plan_owner|
        next false unless block_plan_owner&.organization?
        block_plan_owner.async_adminable_by?(actor)
      end
    end
  end

  def async_parent_org
    async_in_organization?.then do |in_organization|
      next nil unless in_organization
      async_plan_owner.then do |block_plan_owner|
        next nil unless block_plan_owner&.organization?
        block_plan_owner
      end
    end
  end

  # Public: Get all the IDs of users with privileged access to this repository.
  #
  # min_action: - Optional minimum action to restrict which grants are examined.
  #               Default is :read.
  #
  # Note: "Privileged access" is an Abilities term that refers to access gained
  # through any method other than the repository being public. A random user
  # who can see a public repository doesn't have privileged access to it, but
  # if they're added to a team that grants access to the repository (even if
  # it's still just read-only access), they now have privileged access to it.
  #
  # Returns an Array of Integers.
  def user_ids_with_privileged_access(min_action: :read, actor_ids_filter: nil)
    # actor_ids relies on direct abilities on the repository itself with actor type User
    user_ids = actor_ids(type: User, min_action: min_action, actor_ids_filter: actor_ids_filter)

    # If this repo is user-owned, that user always has privileged access to it.
    if owner && owner&.user? && (actor_ids_filter.nil? || actor_ids_filter.include?(owner_id))
      user_ids |= [owner_id]
    end

    # users granted Repository Role with read|write|admin_repo_contents
    user_ids |= fgp_users(min_action, actor_ids_filter)

    # users granted an all repo role with read|write|admin_repo
    ids_all_repo_grants = user_ids_with_all_repo_role_grants(min_action: min_action)
    if !actor_ids_filter.nil?
      ids_all_repo_grants &= actor_ids_filter
    end
    user_ids |= ids_all_repo_grants

    # users granted access via business team org association
    if owner&.organization? && T.cast(owner, Organization).indirect_abilities_enabled?
      indirect_user_ids = fetch_business_team_user_ids(min_action: min_action)
      if actor_ids_filter.present?
        indirect_user_ids &= actor_ids_filter
      end
      user_ids |= indirect_user_ids
    end

    user_ids
  end

  private def fgp_users(min_action, actor_ids_filter)
    permission_query = RolePermission.joins(role: [:user_roles]).where(
      action: "#{min_action}_repo_contents",
      user_roles: { target_type: "Repository", target_id: id, actor_type: "User" },
    )
    permission_query = permission_query.where(user_roles: { actor_id: actor_ids_filter }) if actor_ids_filter
    permission_query.pluck(:actor_id).uniq
  end

  # Public: Get all the IDs of teams with privileged access to this repository.
  #
  # min_action: - Optional minimum action to restrict which grants are examined.
  #               Default is :read.
  #
  # Note: This method only returns teams that have direct access to the repository
  # via a repo role, or an all-repo role grant. It does not include subteams.
  sig { params(min_action: Symbol, actor_ids_filter: T.nilable(T::Array[Integer])).returns(T::Array[Integer]) }
  def team_ids_with_direct_privileged_access(min_action: :read, actor_ids_filter: nil)
    # actor_ids relies on direct abilities on the repository itself
    team_ids = Set.new(actor_ids(type: Team, min_action: min_action, actor_ids_filter: actor_ids_filter))

    if owner&.business&.erp_feature_enabled?(:enterprise_teams_org_roles)
      business_team_ids = actor_ids(type: BusinessTeam, min_action: min_action, actor_ids_filter: actor_ids_filter)
      team_ids += business_team_ids
    end

    direct_all_repo_grants = all_repo_role_grants(min_action)
    team_ids += T.must(direct_all_repo_grants["Team"]) if direct_all_repo_grants.key?("Team")

    if owner&.business&.erp_feature_enabled?(:enterprise_teams_org_roles)
      team_ids += T.must(direct_all_repo_grants["BusinessTeam"]) if direct_all_repo_grants.key?("BusinessTeam")
    end

    team_ids.to_a
  end

  # Public: Get all of the IDs of users with direct access to this repository
  # that are also organization members.
  # action: - optional Symbol action (:read, :write, :admin) to limit actions
  # actor_ids: - optional Array filter to limit the user_ids we check
  #
  # NOTE: This explicitly omits outside collaborators; we select the intersection of
  # repository members and organization members here.
  #
  # For a user owned repository, this returns an empty array. All user owned repository
  # collaborators are outside collaborators
  #
  # Returns [id Integer...]
  def direct_org_member_ids(action: nil, actor_ids: nil)
    return [] unless owner&.organization?
    ability_action = nil
    role_to_filter_out = nil
    role_member_ids_to_remove = []
    role = nil

    # Figure out if action is specified, and if it's a legacy Ability action or a pre-defined
    # fine grained permission role
    if action.present?
      if ::Ability.actions[action]
        ability_action = action
        # :read and :write need to filter out :triage and :maintain, respectively
        role_to_filter_out = Role.preset_by_name(::Role::BASE_ACTION_FOR_ROLE[ability_action])
      elsif Role.valid_system_role?(action)
        role = Role.preset_by_name(action)
      else
        role = RepositoryRole.custom_role_by_name(action, owner: owner)
      end

      # If neither ability_action nor role are defined, a valid action or role wasn't provided
      unless ability_action || role
        raise ArgumentError, "Invalid action for Repository#direct_org_member_ids"
      end
    end

    # if a role is specified only query UserRole and return
    if role
      role_members = UserRole.where(role: role, target: self, actor_type: "User")
      # if actor_ids is specified, we only need the intersection of role_member_ids and actor_ids
      role_member_ids_to_remove = role_members.where(actor_id: Array.wrap(actor_ids)) if actor_ids.present?

      owning_organization  = T.cast(owner, Organization)
      return owning_organization.member_ids(
        actor_ids: role_members.pluck(:actor_id),
        include_indirect_abilities: owning_organization.indirect_abilities_enabled?
      )
    end

    direct_org_member_ids = direct_ability_org_actor_ids(action: action, actor_ids: actor_ids)

    if role_to_filter_out
      role_member_ids_to_remove = UserRole.where(role: role_to_filter_out, target: self, actor_type: "User").pluck(:actor_id)
    end

    direct_org_member_ids - role_member_ids_to_remove
  end

  def direct_ability_org_actor_ids(action: nil, actor_ids: nil)

    direct_ability_scope = Ability
      .where(
        subject_id:   self.id,
        subject_type: "Repository",
        actor_type:   "User",
        priority:     Ability.priorities[:direct])

    # Filter by action and actor_ids if provided
    direct_ability_scope = direct_ability_scope.where(action: Ability.actions[action]) if action.present?
    direct_ability_scope = direct_ability_scope.where(actor_id: Array(actor_ids)) if actor_ids
    direct_ability_user_ids = direct_ability_scope.pluck(:actor_id)

    # Fetch organization members who have direct access to the repository
    org_member_scope = direct_ability_scope
      .annotate("abilities-join-audited")
      .joins("INNER JOIN abilities org ON org.actor_id = abilities.actor_id")
      .where("org.subject_type = 'Organization' and org.subject_id = :organization_id", organization_id: owner_id)
    org_member_ids = org_member_scope.pluck(:actor_id)

    # Fetch business team user IDs who have direct access to the repository
    if organization&.indirect_abilities_enabled?
      business_team_user_ids = fetch_business_team_user_ids(min_action: action)
      business_team_user_ids &= direct_ability_user_ids
      combined_user_ids = (org_member_ids + business_team_user_ids).uniq

      return combined_user_ids
    end

    org_member_ids
  end

  # Public: Get all of the IDs of organization outside collaborators with access to this repository.
  #
  # action: - optional Symbol action (:read, :write, :admin) to limit actions
  # actor_ids: - optional Array filter to limit the user_ids we check
  # Returns [id Integer...]
  def outside_collaborator_member_ids(action: nil, actor_ids: nil)
    return self.member_ids(action: action, actor_ids: actor_ids) unless owner&.organization?

    ability_action = nil
    role_to_filter_out = nil
    role_member_ids_to_remove = []
    role = nil

    # Figure out if action is specified, and if it's a legacy Ability action or a pre-defined
    # fine grained permission role
    if action.present?
      if ::Ability.actions[action]
        ability_action = action
        # :read and :write need to filter out :triage and :maintain, respectively
        role_to_filter_out = Role.preset_by_name(::Role::BASE_ACTION_FOR_ROLE[ability_action])
      elsif Role.valid_system_role?(action)
        role = Role.preset_by_name(action)
      else
        role = RepositoryRole.custom_role_by_name(action, owner: owner)
      end

      # If neither ability_action and role are defined, a valid action or role wasn't provided
      unless ability_action || role
        raise ArgumentError, "Invalid action for Repository#outside_collaborator_member_ids"
      end
    end

    if role
      role_member_ids = UserRole.where(role: role, target: self, actor_type: "User")
      # if actor_ids is specified, we only need the intersection of role_team_ids and actor_ids
      role_member_ids = role_member_ids.where(actor_id: Array.wrap(actor_ids)) if actor_ids.present?

      owning_organization = T.cast(owner, Organization)
      return role_member_ids.pluck(:actor_id) - owning_organization.member_ids(
        include_indirect_abilities: owning_organization.indirect_abilities_enabled?
      )
    end

    if role_to_filter_out
      role_member_ids_to_remove = UserRole.where(role: role_to_filter_out, target: self, actor_type: "User").pluck(:actor_id) if role_to_filter_out
    end

    outside_collaborator_member_ids = outside_collaborator_ability_actor_ids(action: action, actor_ids: actor_ids)
    outside_collaborator_member_ids - role_member_ids_to_remove
  end

  def has_outside_collaborator_members?
    return self.member_ids(limit: 1).any? unless owner&.organization?
    outside_collaborator_ability_actor_ids.any?
  end

  def outside_collaborator_ability_actor_ids(action: nil, actor_ids: nil)
    org_join = ActiveRecord::Base.sanitize_sql_for_conditions(["LEFT JOIN abilities org
      ON org.actor_id       = abilities.actor_id
      AND org.subject_type  = 'Organization'
      AND org.subject_id    = :organization_id", organization_id: owner_id])
    scope = Ability
      .annotate("abilities-join-audited")
      .joins(org_join)
      .where(
        subject_id:   self.id,
        subject_type: "Repository",
        actor_type:   "User",
        priority:     Ability.priorities[:direct])
      .where("org.actor_id IS NULL")

    if action.present?
      scope = scope.where(action: Ability.actions[action])
    end

    if actor_ids
      actor_ids = Array(actor_ids)
      scope = scope.where("abilities.actor_id": actor_ids)
    end

    # Fetch business team user IDs if the feature flag is enabled
    if organization&.indirect_abilities_enabled?
      ability_user_ids = scope.distinct.pluck(:actor_id)
      business_team_user_ids = fetch_business_team_user_ids(min_action: action)
      # Filter business_team_user_ids by actor_ids if provided
      if actor_ids
        business_team_user_ids &= actor_ids
      end
      # Exclude business team user IDs from the result as they should not be treated as outside collaborators
      combined_user_ids = ability_user_ids - business_team_user_ids
      return combined_user_ids
    end

    scope.distinct.pluck(:actor_id)
  end

  def fetch_business_team_user_ids(min_action: nil)
    business_team_user_ids = T.let([], T.untyped)
    async_owner.then do |owner|
      next [] unless owner&.organization?
      # Determine the minimum action rank based on the organization's default repository permission
      # owner is already resolved
      default_permission_rank = Ability::ACTION_RANKING[T.must(T.cast(owner, Organization).default_repository_permission).to_sym]
      min_action_rank = Ability::ACTION_RANKING[min_action || :read]
      # If the organization's default permission rank is smaller than the min_action rank, return an empty array
      if default_permission_rank && default_permission_rank < min_action_rank
        business_team_user_ids = []
      else
        business_team_ids = Orgs.domain.teams.business_team_ids_for_assigned_orgs(organization_id: owner_id)
        business_team_user_ids = Team.member_ids_indexed_by_team_ids(business_team_ids, with_business_teams: true).values.flatten.uniq
      end
    end.sync
    business_team_user_ids
  end

  # Checks if user is a member of the repo or of the owning org
  def async_has_access?(actor)
    self.async_owner.then do |owner|
      next true if owner == actor

      self.async_member?(actor).then do |member|
        next true if member
        next owner.async_member?(actor) if owner.is_a?(Organization)
        next false
      end
    end
  end

  # Internal: Add organization members with default repository permissions
  #
  # This happens via the organization `dependent_added` callback
  #
  # Returns nothing
  def add_members_with_default_repository_permissions
    return unless in_organization?

    T.must(organization).dependent_added(self)
  end

  # Public: Should default repository permissions be propagated from
  #   the owning organization to this repository?
  #
  # Returns Boolean
  def receives_organization_default_repository_permission?
    !advisory_workspace?
  end

  # These IDs should be 'valid' for the entire page load, unless somehow
  # the privileged users changes on page load, therefore safe to cache.
  def privileged_ids
    return @privileged_ids if defined?(@privileged_ids)
    @privileged_ids = user_ids_with_privileged_access(min_action: :read).compact
  end

  def available_assignee_ids(limit: nil)
    user_ids_with_read = privileged_ids

    # https://github.com/github/incident-mysql1-outages/issues/115
    #
    # privileged_ids can be extremely large for large orgs (i.e. > 350k users)
    # passing a limit will arbitrarily limit the return user ids to reduce
    # query timeouts at the expense of potentially missing some users
    user_ids_with_read = user_ids_with_read.take(limit) if limit.present?

    user_ids_with_read - suspended_user_ids(user_ids_with_read)
  end

  def filtered_available_assignee_ids(actor_ids_filter: nil, limit: nil)
    user_ids_with_read = user_ids_with_privileged_access(min_action: :read, actor_ids_filter: actor_ids_filter).compact
    user_ids_with_read = user_ids_with_read.take(limit) if limit.present?

    user_ids_with_read - suspended_user_ids(user_ids_with_read)
  end

  def visible_available_assignee_ids(viewer, limit: nil)
    assignee_ids = available_assignee_ids(limit: limit)

    # The viewer has full access to see the assignable users, including private org members
    # Private and internal repositories should have full access, also.
    return assignee_ids if !public? || member?(viewer) || !owner&.organization? || T.cast(owner, Organization).member?(viewer)

    # If we are at this point it means the viewer is a non-member (or logged out), and viewing a public repository.
    # Therefore we should show the users which have visibly contributed, issue authors, commit contributors and public members.
    public_members_ids = T.cast(owner, Organization).public_members.where(id: assignee_ids).pluck(:id)

    # We're using 2 code paths here depending on the number of assignees
    # The main thing we want to avoid is having a query with a very large IN(...) statement
    issue_author_ids = if assignee_ids.size < VISIBLE_ASSIGNEES_BATCH_THRESHOLD
      Issue.where(repository: self, user_id: assignee_ids).distinct.pluck(:user_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    else
      # When we a LOT of assignees, it is faster to fetch all distinct issue authors
      # and then merge them with the assignees
      author_ids = Issue.where(repository: self).distinct.pluck(:user_id)
      author_ids & assignee_ids
    end

    contribution_user_ids = CommitContributions.domain.contributed_user_ids(
      repository: T.cast(self, Repository), users: assignee_ids, exclude_ghost: true # rubocop:todo GitHub/AvoidCast
    )


    (public_members_ids + issue_author_ids + contribution_user_ids).uniq
  end

  def suspended_user_ids(privileged_ids)
    return [] if privileged_ids.empty?

    # Large orgs can have > 350k users or privileged_ids
    User.where(id: privileged_ids).suspended.pluck(:id)
  end

  # See link for abilities https://github.com/github/pe-workflows/issues/938#issuecomment-451534911
  def can_update_protected_branches?(user)
    owner = T.must(self.owner)
    if owner.organization?
      if business = owner.business
        return true unless GitHub.update_protected_branches_setting_enabled? || FeatureFlag.vexi.enabled_or_raise?(:update_protected_branches_setting, business) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        return true if business.adminable_by?(user) && adminable_by?(user)
        return false if business.members_can_update_protected_branches_policy? && !business.members_can_update_protected_branches?
      end

      return true unless GitHub.update_protected_branches_setting_enabled? || FeatureFlag.vexi.enabled_or_raise?(:update_protected_branches_setting, owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      return true if owner.adminable_by?(user)
      return false if !T.cast(owner, Organization).members_can_update_protected_branches?

      # This really shouldn't be here. We should just be checking for the "business/org admin only" case. We need to remove
      # this whole weird feature.
      self.async_can_edit_repo_protections?(user).sync
    else
      true
    end
  end

  def can_see_deployments?(user)
    return false unless user

    # You can't see the deployments page if there are no deployments,
    # unless you have the pages_deploy_flow flag enabled
    # which shows an empty state on the deployments page
    return false if with_database_error_fallback(fallback: true) { deployments.empty? } && !FeatureFlag.vexi.enabled_or_raise?(:pages_deploy_flow, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    true
  end

  def remove_vulnerability_manager_abilities
    Ability.clear(vulnerability_manager, async: true)
  end

  # Public: Check if the repo's owner is an org that has default
  # repository permission set
  #
  # Returns true/false
  def org_with_default_permission_owner?
    owner.present? && owner&.organization? &&
      T.cast(owner, Organization).default_repository_permission != :none
  end

  # Public: Checks if a user can invite collaborators to an organisation repository
  #
  # user  - User to be checked
  #
  # Returns boolean
  def cannot_invite_outside_collaborators?(user)
    return false unless in_organization?

    organization = T.must(self.organization)
    (
      # EMUs do not support outside collaborators, they use repository collaborators
      organization.enterprise_managed_user_enabled? ||
      # repo invites restricted for org members
      (
        organization.can_restrict_repo_invites? &&
        !organization.members_can_invite_outside_collaborators? &&
        !organization.adminable_by?(user)
      ) || restricted_by_member_privileges?(user)
    )
  end

  # Enterprise owners can prevent both members and org owners from inviting outside collaborators
  private def restricted_by_member_privileges?(user)
    return false unless organization&.business.present?
    return false unless organization&.enterprise_admins_only_can_invite_outside_collaborators?
    !organization&.business&.adminable_by?(user)
  end

  def evaluate_action(action)
    if Repository::VALID_ORG_REPO_ACTIONS_AND_ROLES.include? action
      action
    elsif Role.valid_system_role?(action)
      Repository.permission_to_action(action)
    else
      RepositoryRole.custom_role_by_name(action, owner: owner).name
    end
  end

  def target_for_conditional_access
    owner
  end

  def async_target_for_conditional_access
    async_owner
  end

  private def can_modify_delete_branch_setting?(user)
    if user.user?
      async_adminable_by?(user).sync
    elsif user.bot?
      resources.administration.writable_by?(user)
    else
      false
    end
  end

  # Internal: Is the permission greater or equal in rank than the target permission.
  # Both inputs can be an Ability (e.g. read), a Role (e.g. triage) or a custom role.
  #
  # - permission: a String or Symbol.
  # - target: a String or Symbol.
  #
  # Returns a Boolean.
  private def permission_greater_than_target?(permission, target:)
    return false if permission.nil?

    perm = permission.to_sym
    target = target.to_sym
    return true if perm == target

    permission =
      if Role.valid_system_role?(perm)
        Role.preset_by_name(perm)
      else
        RepositoryRole.custom_role_by_name(perm, owner: organization)
      end

    permission.target_greater_than_or_equal_to_other_role?(other_role: target)
  end
end
