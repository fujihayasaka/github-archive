# typed: true
# frozen_string_literal: true

module Repository::PermissionExportDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Returns a list of grants that the user has received from a team membership
  def team_grants(user, viewer)
    access = Organization::RepositoryPermissions.new(self, user)
    promises = access.all_team_abilities_for_repository.map do |derived_ability|
      Platform::Loaders::ActiveRecord.load(Team, derived_ability.actor_id).then do |team|
        source_team_id = derived_ability.original_ability.actor_id
        Platform::Loaders::Permissions::DirectUserRoleOnRepositoryForActor.load(actor_id: source_team_id, actor_type: "Team", repo_id: id).then do |user_role|
          { "source" => team,
            "permission" => derived_ability.action,
            "roleName" => user_role&.role&.name || derived_ability.action }
        end
      end
    end
    Promise.all(promises)
  end

  # Returns a list of grants that the user has received through their org membership
  # Users who have access to a repository through org grants are org members or admins
  def org_grants(user, viewer)
    Platform::Loaders::Permissions::DirectAbilitiesOnSubjectForActor.load(
      subject_type: "Organization",
      subject_id: owner&.id,
      actor_type: "User",
      actor_id: user.id

    ).then do |abilities|
      abilities.map { |a| { "source" => owner, "permission" => a.action } }
    end
  end

  def repo_grants(user, viewer)
    # There are never multiple user->repo ability records: https://data.githubapp.com/sql/0d7c7bf6-3b5b-4035-baef-7fdc236e9098#
    # Same for teams: https://data.githubapp.com/sql/8f0a3dd2-a803-49d9-9c64-2aee2f9e5541#
    grants = []

    promise = Platform::Loaders::Permissions::DirectAbilitiesOnSubjectForActor.load(
      subject_type: "Repository",
      subject_id: id,
      actor_type: "User",
      actor_id: user.id
    ).then do |abilities|
      ability = abilities&.first&.action

      if ability
        Platform::Loaders::Permissions::DirectUserRoleOnRepositoryForActor.load(actor_id: user.id, actor_type: "User", repo_id: id).then do |user_role|
          grant = { "source" => self, "permission" => ability, "roleName" => ability }
          role = user_role&.role
          if role&.target_greater_than_or_equal_to_other_role?(other_role: ability)
            grant["roleName"] = role.name
          end
          grants << grant
        end
      end
    end

    promise = promise.then do
      if owning_organization_id
        Platform::Loaders::Permissions::DirectAbilitiesOnSubjectForActor.load(
          actor_id: user.id,
          actor_type: "User",
          subject_id: owning_organization_id,
          subject_type: "Organization")
      else
        Promise.resolve([])
      end
    end

    promise.then do |org_abilities|
      if admin_ability = org_abilities.find { |a| a.action.to_sym == :admin }
        # this makes more sense as an org grant... but this is the way things are.
        grants << { "source" => self, "permission" => admin_ability.action, "roleName" => admin_ability.action }
      end
      grants
    end
  end

  # Returns a list of all sources of a user's access to this repository and the permission level granted
  # Possible permission levels are "admin", "write", and "read"
  # Possible sources are Team, Organization, and Repository objects
  def permission_sources(user, viewer)
    async_permission_sources(user, viewer).sync
  end

  def async_permission_sources(user, viewer)
    return [] unless owner&.organization? && can_view_permission_sources?(viewer)
    Promise.all([org_grants(user, viewer), repo_grants(user, viewer), team_grants(user, viewer)]).then do |org, repo, team|
      org + repo + team
    end
  end

  def can_view_permission_sources?(viewer)
    owner&.resources.organization_administration.readable_by?(viewer) && owner&.resources.members.readable_by?(viewer)
  end
end
