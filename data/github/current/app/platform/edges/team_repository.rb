# typed: false
# frozen_string_literal: true

module Platform
  module Edges
    class TeamRepository < Edges::Base
      description "Represents a team repository."

      minimum_accepted_scopes ["read:org"]

      field :node, Objects::Repository, null: false

      field :permission, Enums::RepositoryPermission, description: "The permission level the team has on the repository", null: false

      def permission
        repo = @object.node
        team = @object.parent
        team.async_most_capable_action_or_role_for(repo)
      end

      field :permission_name, String, description: "The name of the permission that the team has on the repository. It can include custom roles",
        null: true, visibility: :internal

      def permission_name
        repo = @object.node
        team = @object.parent
        repo.async_action_or_role_level_for(team).then do |role|
          role.present? ? role.upcase : nil
        end
      end

      field :inherited_permission_origin, Objects::Team, visibility: :internal, description: "The parent team that grants inherited permission to this repository", null: true

      def inherited_permission_origin
        async_inherited_action_or_role.then do |action_or_role|
          next unless action_or_role
          action_or_role.async_actor
        end
      end

      field :inherited_permission, Enums::RepositoryPermission, visibility: :internal, description: "The inherited permission level the team has on the repository", null: true

      def inherited_permission
        async_inherited_action_or_role.then do |action_or_role|
          next unless action_or_role
          if action_or_role.is_a?(UserRole)
            action_or_role.role.action_name
          else
            action_or_role.action_name
          end
        end
      end

      field :inherited_permission_name, String, visibility: :internal, description: "The inherited permission level the team has on the repository, with custom roles", null: true

      def inherited_permission_name
        async_inherited_action_or_role.then do |action_or_role|
          next unless action_or_role
          if action_or_role.is_a?(UserRole)
            action_or_role.role.name
          else
            action_or_role.action_name
          end
        end
      end

      # This returns the most capable ability or repository role that this team has
      # inherited from an ancestor for a repo.
      def async_inherited_action_or_role
        repo = @object.node
        team = @object.parent
        return unless team.ancestor_ids.present?

        promises = [
          Loaders::MostCapableInheritedTeamRepositoryAbilities.load(team: team, repo: repo),
          Loaders::Permissions::MostCapableInheritedTeamRepositoryUserRole.load(team: team, repo: repo),
        ]

        Promise.all(promises).then do |ability, user_role|
          if user_role.present? && ability.nil?
            if user_role.role.is_a?(OrganizationRole)
              next user_role
            end
          end

          next unless ability
          next ability unless user_role.present?

          user_role.async_role.then do |role|
            if role.action_rank >= Ability::ACTION_RANKING[ability.action.to_sym]
              user_role
            else
              ability
            end
          end
        end
      end
    end
  end
end
