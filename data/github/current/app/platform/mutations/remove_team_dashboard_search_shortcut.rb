# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveTeamDashboardSearchShortcut < Mutations::Base
      description "Remove a search shortcut on the respective team's dashboard."
      minimum_accepted_scopes ["write:org"]
      required_capabilities [:mobile_only_schema_mask]

      argument :shortcut_id, ID, "The ID of the shortcut to remove.",
        required: true, loads: Objects::TeamSearchShortcut

      field :dashboard, Objects::TeamDashboard, "The removed shortcut's team dashboard.", null: true
      field :shortcut, Objects::TeamSearchShortcut, "The shortcut that was removed.", null: true

      def self.async_api_can_modify?(permission, shortcut:, **inputs)
        Promise.all([shortcut.dashboard.team.async_member?(permission.viewer), shortcut.dashboard.team.async_updatable_by?(permission.viewer)]).then do |is_member, can_update|
          is_member || can_update
        end
      end

      def resolve(shortcut:)
        dashboard = shortcut.dashboard
        shortcut.destroy!

        {
          dashboard: dashboard,
          shortcut: shortcut
        }
      end
    end
  end
end
