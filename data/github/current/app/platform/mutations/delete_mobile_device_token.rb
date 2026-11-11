# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteMobileDeviceToken < Platform::Mutations::Base
      include Helpers::Newsies

      description "Delete a mobile device token."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      argument :service, Enums::PushNotificationService, "The push notification service that issued the device token.", required: true
      argument :device_token, String, "The device token to delete.", required: true

      field :success, Boolean, "Did the operation succeed?", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      #
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, *_)
        permission.access_allowed?(
          :update_user_notification_settings,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def resolve(service:, device_token:)
        { success: Notifyd::DeviceTokensService.delete(user_id: context[:viewer].id, token: device_token) }
      end
    end
  end
end
