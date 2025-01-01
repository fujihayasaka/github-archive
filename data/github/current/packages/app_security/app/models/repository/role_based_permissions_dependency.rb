# typed: true
# frozen_string_literal: true

module Repository::RoleBasedPermissionsDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  BATCH_SIZE = 1000

  included do
    T.bind(self, T.class_of(Repository))

    # this will also define async_batch_most_capable_user_role_for_actor
    batch_method(:most_capable_user_role_for_actor) do |repos, actor|
      entries = repos.map { |repo| [actor, repo] }

      roles_by_actor_and_repo = Platform::Loaders::Permissions::MostCapableUserRoleOnRepositoryForActor.new(actor.class).fetch(entries)

      repos.index_with do |repo|
        roles_by_actor_and_repo[[actor, repo]]
      end
    end
  end

  def async_most_capable_user_role_for_multiple_actors(actors)
    raise ArgumentError, "actors must all have same class" unless actors.all? { |actor| actor.class == actors.first.class }
    entries = actors.map { |actor| [actor, self] }
    roles_by_actor_and_repo = Platform::Loaders::Permissions::MostCapableUserRoleOnRepositoryForActor.new(actors.first.class).fetch(entries)
    actor_roles = roles_by_actor_and_repo.map do |actor_repo_role|
      actor_repo, role = actor_repo_role
      actor, repo = actor_repo
      [actor, role]
    end
    Promise.resolve(actor_roles)
  end

  # Public: Returns the most capable action level or repository role name that an actor has on this repository.
  #
  # actor - The User or Team to check access for.
  # include_custom_roles: If false, returns the base role of the custom role instead.
  #         Even though it's an antipattern to hardcode checks on role names, the unfortunate reality
  #         is that many places in the monolith do this. So this argument is useful for callsites that
  #         need to check if the actor effectively has read/triage/write/maintain/admin
  #
  # Returns a Promise<Symbol|nil>.
  def async_action_or_role_level_for(actor, include_employee_granted_permissions: true, include_custom_roles: true)
    async_access_level_for(actor, include_employee_granted_permissions: include_employee_granted_permissions).then do |access_level|
      next Promise.resolve(nil) unless access_level.present?
      next Promise.resolve(access_level) unless actor.present?

      # Skip checking roles if actor has admin access level since that is the
      # most capable action level
      next Promise.resolve(access_level) if access_level == :admin

      async_role_for(actor, include_custom_roles).then do |most_capable_role|
        next access_level unless most_capable_role.present?

        if most_capable_role.action_rank >= Ability::ACTION_RANKING[access_level]
          most_capable_role.name.to_sym
        else
          access_level
        end
      end
    end
  end

  # Public: returns the most capable action levels and repository role names for a set of users on this repository.
  #
  # actors - An array of Users to get access levels for
  # Returns a [HighestActions, HighestRoles] tuple,
  #  where HighestActions is Hash<int, string> associating user_ids with action levels,
  #  and HighestRoles is Hash<int, string> associating user_ids with role names.
  def batch_action_and_role_level_for(actors)
    role_map = {}
    actor_highest_action_map = {}
    actors.each_slice(BATCH_SIZE) do |actor_batch|
      role_batch = self.async_roles_for(actor_batch).sync.to_h
      action_batch = Authorization.service.most_capable_abilities_between_multiple_actors_and_subjects(
        actor_type: User,
        actor_ids: actor_batch.map { |m| m.id }.to_a,
        subject_type: Repository,
        subjects: [self],
      ).map { |a| [a.actor_id, a.action] }.to_h

      role_map.merge!(role_batch)
      actor_highest_action_map.merge!(action_batch)
    end

    owner = self.owner
    if owner.present? && owner.user? && actors.map(&:id).include?(owner.id)
      # user-owned repositories don't have an ability record for the owner
      # see https://github.com/github/authorization/issues/1047
      actor_highest_action_map[owner.id] = "admin"
    end
    actor_highest_role_map = actor_highest_action_map.clone

    actors.each do |actor|
      action = actor_highest_action_map[actor.id]
      action_rank = Ability::ACTION_RANKING[action&.to_sym] || -1
      role = role_map[actor.id]
      if role && role.action_rank >= action_rank
        actor_highest_action_map[actor.id] = role.action_name
        actor_highest_role_map[actor.id] = role.name
      end
    end

    [actor_highest_action_map, actor_highest_role_map]
  end

  # Public: Returns the most capable action or repository role that an actor has on this repository.
  #
  # actor - The User or Team to check access for.
  #
  # Returns a Promise<Symbol|nil>.
  def async_most_capable_action_or_role_for(actor)
    # todo(bencoomes) - async_ability_for is not async and would cause N+1s
    # however, all current callsites for this method call `.sync` on the result without any chance for batching
    async_ability_for(actor).then do |access_level|
      next Promise.resolve(nil) unless access_level.present?
      next Promise.resolve(access_level) unless actor.present?

      async_role_for(actor).then do |most_capable_role|
        next access_level unless most_capable_role.present?

        if most_capable_role.action_rank >= Ability::ACTION_RANKING[access_level.action.to_sym]
          most_capable_role
        else
          access_level
        end
      end
    end
  end

  # Public: Returns the most capable Role that an actor has on this repository.
  # .       The base role is returned for All repo Org Roles or custom role unless requested (see below)
  # actor - The User or Team to check access for.
  # include_custom_roles - If custom roles should be included, or if their base role should be used instead
  #
  # Returns a Promise<Role|nil>.
  def async_role_for(actor, include_custom_roles = true)
    async_owner.then do |org|
      next unless org&.organization?

      async_batch_most_capable_user_role_for_actor(actor).then do |most_capable_role|
        next unless most_capable_role.present?
        most_capable_role.async_role.then do |role|
          role.async_base_role.then do |base_role|
            if role.target_type == "Organization"
              base_role
            elsif role.custom? && !include_custom_roles
              base_role
            else
              role
            end
          end
        end
      end
    end
  end

  # Returns the system Repository Role assigned to an actors
  # If the most capable role is an Organization All Repo Role or
  # custom repo role, the base role is returned (except in the case of
  # custom repo role, if include_custom_roles is true)
  def async_roles_for(actors, include_custom_roles = true)
    async_owner.then do |org|
      next unless org&.organization?

      async_most_capable_user_role_for_multiple_actors(actors).then do |actor_roles|
        promises = actor_roles.map do |actor_role|
          next unless actor_role.present?
          actor, user_role = actor_role
          user_role.async_role.then do |role|
            role.async_base_role.then do |base_role|
              if role.target_type == "Organization"
                [actor.id, base_role]
              elsif role.custom? && !include_custom_roles
                [actor.id, base_role]
              else
                [actor.id, role]
              end
            end
          end
        end
        Promise.all(promises)
      end
    end
  end

  # Public: Returns the most capable Ability that an actor has on this repository.
  #
  # actor - The User or Team to check access for.
  #
  # Returns a Promise<Role|nil>.
  def async_ability_for(actor)
    return Promise.resolve(nil) if unpersisted?
    return Promise.resolve(nil) if actor.is_a?(User) && !actor.user?

    ability = Authorization.service.most_capable_ability_between(actor: actor, subject: self)

    Promise.resolve(ability)
  end

  # The class name persisted as `target_type` when a UserRole is created
  # with this object as target.
  def user_role_target_type
    "Repository"
  end
end
