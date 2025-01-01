# typed: true
# frozen_string_literal: true

module Team::RoleBasedPermissionsDependency
  extend T::Helpers
  requires_ancestor { Team }
  include GitHub::BatchMethod
  extend ActiveSupport::Concern

  included do
    batch_method(:org_roles) do |teams|
      org_id = teams.first.organization_id
      raise ArgumentError, "teams must all belong to the same org" unless teams.all? { |team| team.organization_id == org_id }

      org_roles = UserRole.where(
        actor_type: "Team",
        actor_id: teams.map(&:id),
        target_type: "Organization",
        target_id: org_id
      ).includes(role: :permissions).group_by(&:actor_id)

      teams.index_with { |team| org_roles[team.id]&.map(&:role) || [] }
    end
  end

  # Public: Returns the most capable action or repository role that this team has on a repository.
  #
  # repository - The Repository to check access for.
  # include_custom_roles - True if a custom role should be returned. False if
  #                        the base role should be used.
  # role_priority - True will give priority to roles when comparing abilities
  #                 and roles of equal rank.
  #
  # Returns a Promise<String|nil>.
  def async_most_capable_action_or_role_for(repository, include_custom_roles: false, role_priority: false)
    promises = [
      Platform::Loaders::MostCapableTeamRepositoryAbilities.load(team: self, repo: repository),
      async_role_for(repository, include_custom_roles: include_custom_roles),
      repository.async_owner,
    ]

    # async_role_for returns the base_role of a custom RepositoryRole or OrganizationRole
    Promise.all(promises).then do |ability, base_role|
      next base_role.action_name if base_role.present? && ability.nil?
      next unless ability.present?
      ability_action = ability.action_name
      next ability_action unless base_role.present?

      if role_priority
        if base_role.action_rank >= Ability::ACTION_RANKING[ability.action.to_sym]
          base_role.name
        else
          ability.action_name
        end
      else
        if base_role.action_rank > Ability::ACTION_RANKING[ability.action.to_sym]
          base_role.name
        else
          ability.action_name
        end
      end
    end
  end

  # Public: Returns the most capable Role that this team has on a repository.
  #
  # repository - The Repository to check access for.
  # include_custom_roles - True if a custom role should be returned. False if
  #                        the base role should be used.
  #
  # Returns a Promise<Role|nil>.
  def async_role_for(repository, include_custom_roles: false)
    repository.async_owner.then do |owner|
      next unless owner.organization?

      Platform::Loaders::Permissions::MostCapableUserRoleOnRepositoryForActor.load(
        actor: self,
        repo: repository,
      ).then do |most_capable_role|
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

  # Public: Finds a number of repositories based on and sorted by the
  # role action.
  #
  # limit - The number of roles to return
  #
  # Returns a Hash {repo_id => role display name}
  def action_or_role_over_repositories(limit = 25)
    abilities = Ability.where(
      subject_type: "Repository",
      actor_type: "Team",
      actor_id: id_and_ancestor_ids,
      priority: Ability.priorities[:direct]
    ).order(action: :desc).limit(limit)

    abilities_by_repo = abilities.each_with_object({}) do |a, res|
      repo_id = a.subject_id
      if res[repo_id].blank?
        res[repo_id] = a.action
        next
      end

      res[repo_id] = a.action if Ability::ACTION_RANKING[res[repo_id].to_sym] < Ability::ACTION_RANKING[a.action.to_sym]
    end

    # all user_roles are backed by abilities,
    # so if there is a user_role, we are ensured to have a backing ability
    roles = UserRole.where(
      target_type: "Repository",
      actor_type: "Team",
      target_id: abilities_by_repo.keys,
      actor_id: id_and_ancestor_ids,
    ).includes(:role)

    highest_role_by_repo = roles.group_by(&:target_id).map do |repo_id, user_roles|
      [repo_id, RepositoryRole.highest_role(user_roles.map(&:role))]
    end.to_h

    results = {}
    abilities_by_repo.keys.each do |repo_id|
      role = highest_role_by_repo[repo_id]
      ability = abilities_by_repo[repo_id]
      if role&.target_greater_than_or_equal_to_other_role?(other_role: ability)
        results[repo_id] = role.display_name
      else
        results[repo_id] = ability.titleize
      end
    end

    results
  end
end
