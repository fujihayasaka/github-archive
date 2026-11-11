# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetMobileLiveActivityStartToken < Platform::Mutations::Base
      description "Set a push-to-start token for iOS live activity updates."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      argument :device_token, String, description: "The device token for push notifications.", required: true
      argument :type, Enums::MobileLiveActivityType, description: "The type of push notification.", required: true, as: :live_activity_type
      argument :token, String, description: "The push-to-start token.", required: true

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

      def resolve(device_token:, live_activity_type:, token:)
        user_id = context[:viewer].id
        raise Errors::Unprocessable.new("User must exist") unless user_id

        response = Notifyd::LiveActivityTokensService.set_start_token(
          user_id:,
          device_token:,
          live_activity_type:,
          token:
        )

        raise Errors::Unprocessable.new("Failed to set the live activity push-to-start token.") unless response.present?

        {
          success: response
        }
      end
    end
  end
end
