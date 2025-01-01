# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveDashboardSearchShortcut < Mutations::Base
      description "Remove a dashboard search shortcut for the current viewer."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      argument :shortcut_id, ID, "The ID of the shortcut to remove.",
        required: true, loads: Objects::SearchShortcut

      field :dashboard, Objects::UserDashboard, "The removed shortcut's dashboard.", null: true
      field :shortcut, Objects::SearchShortcut, "The shortcut that was removed.", null: true

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

      def resolve(shortcut:)
        shortcut.destroy!
        {
          dashboard: context[:viewer].dashboard,
          shortcut: shortcut
        }
      end
    end
  end
end
