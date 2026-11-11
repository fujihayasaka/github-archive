# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetMobileLiveActivityPushToken < Platform::Mutations::Base
      docs_category :meta
      description "Set a push token for iOS live activity updates."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      argument :device_token, String, description: "The device token for push notifications.", required: true
      argument :type, Enums::MobileLiveActivityType, description: "The type of push notification.", required: true, as: :live_activity_type
      argument :token, String, description: "The push token.", required: true
      argument :session_id, String, description: "The session ID for the live activity.", required: true

      field :success, Boolean, description: "Was the operation successful?", null: true

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

      def resolve(device_token:, live_activity_type:, token:, session_id:)
        user_id = context[:viewer].id
        raise Errors::Unprocessable.new("User must exist") unless user_id

        response = Notifyd::LiveActivityTokensService.set_push_token(
          user_id:,
          device_token:,
          live_activity_type:,
          token:,
          session_id:
        )

        raise Errors::Unprocessable.new("Failed to set the live activity push token") unless response.present?

        {
          success: response
        }
      end
    end
  end
end
