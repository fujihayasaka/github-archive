# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddMobileDeviceToken < Platform::Mutations::Base
      include Helpers::Newsies

      description "Associate a mobile device token with the current viewer."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      argument :service, Enums::PushNotificationService, "The push notification service that issued the device token.", required: true
      argument :device_token, String, "The device token.", required: true
      argument :device_name, String, "The name of the device.", required: false
      argument :encryption_key, String, "The encryption key for the device token. Base64 encoded.", required: false
      argument :hmac_key, String, "The HMAC key for the device token. Base64 encoded.", required: false

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

        encryption_key = kwargs.fetch(:encryption_key, "")
        hmac_key = kwargs.fetch(:hmac_key, "")

        if encryption_key.present? != hmac_key.present?
          raise Errors::Unprocessable.new("Arguments encryption_key and hmac_key must be provided together")
        end

        response = Notifyd::DeviceTokensService.set(user_id:, oauth_access_id:, token:, encryption_key:, hmac_key:)
        raise Errors::Unprocessable.new("Failed to add the mobile device token") unless response.present?
        {
          success: response,
        }
      end
    end
  end
end
