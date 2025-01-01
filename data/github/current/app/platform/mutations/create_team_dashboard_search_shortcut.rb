# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateTeamDashboardSearchShortcut < Mutations::Base
      description "Create a new search shortcut for the given team dashboard."

      minimum_accepted_scopes ["write:org"]
      mobile_only true
      extras [:execution_errors]

      argument :team_id, ID, "The ID of the team.", required: true, loads: Objects::Team
      argument :name, String, "The name of the shortcut.", required: true
      argument :query, String, "The search query for the shortcut.", required: false, default_value: ""
      argument :description, String, "The description for the shortcut.", required: false, default_value: ""
      argument :search_type, Enums::SearchShortcutType, "The search type for the shortcut.", required: true
      argument :icon, Enums::SearchShortcutIcon, "The icon for the shortcut.", required: true
      argument :color, Enums::SearchShortcutColor, "The color for the shortcut.", required: true
      argument :scoping_repository, Inputs::RepositoryNameWithOwner, <<~DESC, required: false
        The repository acting as a scope for filtering shortcut query terms.
      DESC

      error_fields

      field :dashboard, Objects::TeamDashboard, "The team dashboard owning the shortcut", null: true
      field :shortcut, Objects::TeamSearchShortcut, "The created search shortcut.", null: true
      field :shortcut_edge, Objects::TeamSearchShortcut.edge_type, "The edge from the team dashboard to the created search shortcut.", null: true

      def self.async_api_can_modify?(permission, team:, **inputs)
        Promise.all([team.async_member?(permission.viewer), team.async_updatable_by?(permission.viewer)]).then do |is_member, can_update|
          is_member || can_update
        end
      end

      def resolve(execution_errors:, team:, **inputs)
        viewer = context[:viewer]

        dashboard = team.dashboard || ::TeamDashboard.create!(team: team)

        scoping_repo =
          if inputs[:scoping_repository].present?
            Helpers::RepositoryByNwo.async_repository_with_owner(
              login: inputs.dig(:scoping_repository, :owner),
              name: inputs.dig(:scoping_repository, :name),
              permission: context[:permission],
              viewer: context[:viewer],
              follow_repo_redirect: true
            ).sync
          end

        shortcut = dashboard.shortcuts.build({
          name: inputs[:name],
          description: inputs[:description],
          query: inputs[:query].to_s,
          search_type: inputs[:search_type],
          color: inputs[:color],
          icon: inputs[:icon],
          scoping_repository_id: scoping_repo&.id
        })

        if shortcut.valid?
          begin
            shortcut_connection = Platform::ConnectionWrappers::Relation.new(dashboard.shortcuts, context: context)
            shortcut_edge = GraphQL::Pagination::Connection::Edge.new(shortcut, shortcut_connection)

            dashboard.prioritize_dependent!(shortcut, position: :bottom)
            {
              dashboard: dashboard,
              shortcut: shortcut,
              shortcut_edge: shortcut_edge,
              errors: []
            }
          rescue GitHub::Prioritizable::Context::LockedForRebalance
            raise Errors::ServiceUnavailable.new("This team dashboard is temporarily locked for maintenance. Please try again.")
          end
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
