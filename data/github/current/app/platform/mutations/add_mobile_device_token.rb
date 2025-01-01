# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    class AddMobileDeviceToken < Platform::Mutations::Base
      include Helpers::Newsies

      description "Associate a mobile device token with the current viewer."
      minimum_accepted_scopes ["user"]
      mobile_only true

      argument :service, Enums::PushNotificationService, "The push notification service that issued the device token.", required: true
      argument :device_token, String, "The device token.", required: true
      argument :device_name, String, "The name of the device.", required: false

      field :success, Boolean, "Did the operation succeed?", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      #
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user_notification_settings,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def resolve(**kwargs)
        user_id = context[:viewer].id
        raise Errors::Unprocessable.new("User must exist") unless user_id
        oauth_access_id = context[:viewer].oauth_access.try(:id)
        raise Errors::Unprocessable.new("Oauth access must exist") unless oauth_access_id
        token = kwargs[:device_token]
        raise Errors::Unprocessable.new("Device token must exist") unless token

        response = Notifyd::DeviceTokensService.set(user_id:, oauth_access_id:, token:)
        raise Errors::Unprocessable.new("Failed to add the mobile device token") unless response.present?
        { success: response }
      end
    end
  end
end
