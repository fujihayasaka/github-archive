# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class EnableWebNotifications < Platform::Mutations::Base
      include Helpers::Newsies

      description "Generally enables the user's web notifications."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      field :success, Boolean, "Did the operation succeed?", null: true
      field :viewer, Objects::User, "The user whose settings were updated.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        user = permission.viewer
        permission.access_allowed?(
          :update_user_notification_settings,
          resource: user,
          current_org: nil,
          current_repo: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def resolve(**inputs)
        viewer = context[:viewer]

        unless Notifications::Settings.enable_web(viewer)
          raise Errors::ServiceUnavailable.new("Notification settings are currently unavailable.")
        end

        {}
      end
    end
  end
end
