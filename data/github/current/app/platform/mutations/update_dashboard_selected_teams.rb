# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateDashboardSelectedTeams < Mutations::Base
      description "Updates the selected teams for the current viewers user dashboard."
      minimum_accepted_scopes ["user", "read:org"]
      required_capabilities [:mobile_only_schema_mask]
      extras [:execution_errors]

      argument :team_ids, [ID], "The IDs of the teams to select.", required: true, loads: Objects::Team
      error_fields

      field :dashboard, Objects::UserDashboard, "The dashboard owned by the viewer", null: true
      field :dashboard_team_edges, [Objects::Team.edge_type], "The new selected team edges.", null: true
      field :removed_team_ids, [ID], "The ids of the teams that were removed from the selected teams.", null: true

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false
        )
      end

      def resolve(execution_errors:, teams:, **inputs)
        dashboard = context[:viewer].dashboard || ::UserDashboard.create!(user: context[:viewer])
        # return all the teams that have been removed from the selection
        old_selected_teams = dashboard.selected_teams - teams
        dashboard.selected_teams = teams.uniq(&:id)
        removed_team_ids = old_selected_teams.uniq(&:id).map(&:global_relay_id)
        if dashboard.valid?
          dashboard.save!
          selected_teams_relation = dashboard.selected_teams
          selected_teams_connection_connection = Platform::ConnectionWrappers::Relation.new(selected_teams_relation, context: context)

          new_selected_team_edges = dashboard.selected_teams.map do |team|
            GraphQL::Pagination::Connection::Edge.new(team, selected_teams_connection_connection)
          end

          {
            dashboard: dashboard,
            dashboard_team_edges: new_selected_team_edges,
            removed_team_ids: removed_team_ids,
            errors: []
          }
        else
          {
            dashboard: nil,
            dashboard_team_edges: nil,
            removed_team_ids: nil,
            errors: Platform::UserErrors.mutation_errors_for_model(dashboard)
          }
        end
      end
    end
  end
end
