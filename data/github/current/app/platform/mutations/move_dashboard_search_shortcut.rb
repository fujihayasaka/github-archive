# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MoveDashboardSearchShortcut < Mutations::Base
      description "Move a dashboard shortcut to a position behind another for the current viewer."
      minimum_accepted_scopes ["user"]
      mobile_only true

      argument :shortcut_id, ID, "The ID of the shortcut to move.", required: true, loads: Objects::SearchShortcut
      argument :after_shortcut_id, ID, <<~DESC, required: false, loads: Objects::SearchShortcut
        Place the shortcut after the shortcut with this ID. Pass null to place at top.
      DESC

      field :dashboard, Objects::UserDashboard, "The dashboard owning the shortcuts.", null: true
      field :shortcut_edge, Objects::SearchShortcut.edge_type, "The new edge of the moved shortcut.", null: true

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

      def resolve(shortcut:, **inputs)
        dashboard = context[:viewer].dashboard

        if (after_shortcut = inputs[:after_shortcut]).present?
          if after_shortcut.dashboard_id != shortcut.dashboard_id
            raise Errors::NotFound.new(
              "Could not resolve to a node with the global id of '#{after_shortcut.global_relay_id}'."
            )
          end

          if after_shortcut.priority.nil?
            raise Errors::Validation.new("The afterShortcut must be prioritized")
          end
        end

        position = :top unless after_shortcut

        begin
          dashboard.prioritize_dependent!(shortcut, after: after_shortcut, position: position)
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          raise Errors::ServiceUnavailable.new("This user dashboard is temporarily locked for maintenance. Please try again.")
        end

        shortcuts_connection = ConnectionWrappers::Relation.new(
          dashboard.shortcuts,
          parent: dashboard,
          context: context
        )

        {
          dashboard: dashboard,
          shortcut_edge: GraphQL::Pagination::Connection::Edge.new(shortcut, shortcuts_connection)
        }
      end
    end
  end
end
