# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTeamDashboardSearchShortcut < Mutations::Base
      description "Update a team dashboard search shortcut for the current viewer."
      minimum_accepted_scopes ["write:org"]
      required_capabilities [:mobile_only_schema_mask]
      extras [:execution_errors]

      argument :shortcut_id, ID, "The ID of the shortcut to update.", required: true, loads: Objects::TeamSearchShortcut

      # Not using the input/attributes class to allow all fields to be null, with the exception of the team shortcut above.
      argument :name, String, "The name of the shortcut.", required: false
      argument :description, String, "The description of the shortcut.", required: false
      argument :query, String, "The search query for the shortcut.", required: false
      argument :search_type, Enums::SearchShortcutType, "The search type for the shortcut.", required: false
      argument :icon, Enums::SearchShortcutIcon, "The icon for the shortcut.", required: false
      argument :color, Enums::SearchShortcutColor, "The color for the shortcut.", required: false
      argument :scoping_repository, Inputs::RepositoryNameWithOwner, <<~DESC, required: false
        The repository acting as a scope for filtering shortcut query terms.
      DESC

      field :dashboard, Objects::TeamDashboard, "The dashboard owning the shortcut.", null: true
      field :shortcut, Objects::TeamSearchShortcut, "The updated search shortcut.", null: true

      error_fields

      def self.async_api_can_modify?(permission, shortcut:, **inputs)
        Promise.all([shortcut.dashboard.team.async_member?(permission.viewer), shortcut.dashboard.team.async_updatable_by?(permission.viewer)]).then do |is_member, can_update|
          is_member || can_update
        end
      end

      def resolve(execution_errors:, shortcut:, **inputs)
        dashboard = shortcut.dashboard
        team = dashboard.team
        viewer = context[:viewer]

        if inputs.empty?
          raise Errors::Unprocessable.new("Must provide at least one attribute to update.")
        end

        attrs = inputs.slice(:name, :description, :query, :search_type, :icon, :color)

        if inputs.key?(:scoping_repository)
          if inputs.fetch(:scoping_repository).nil?
            attrs[:scoping_repository_id] = nil
          else
            scoping_repo = Helpers::RepositoryByNwo.async_repository_with_owner(
              login: inputs.dig(:scoping_repository, :owner),
              name: inputs.dig(:scoping_repository, :name),
              permission: context[:permission],
              viewer: context[:viewer],
              follow_repo_redirect: true
            ).sync

            attrs[:scoping_repository_id] = scoping_repo.id
          end
        end

        if shortcut.update(attrs)
          {
            dashboard: dashboard,
            shortcut: shortcut,
            errors: []
          }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(shortcut, execution_errors)

          {
            dashboard: nil,
            shortcut: nil,
            errors: Platform::UserErrors.mutation_errors_for_model(shortcut)
          }
        end
      end
    end
  end
end
