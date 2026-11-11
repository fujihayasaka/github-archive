# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ResetCopilotLiveActivitySetting < Platform::Mutations::Base
      docs_category :copilot
      description "Reset the Copilot Live Activity push notification setting to its unconfigured state. " \
        "Temporary development tool — will be removed once client development is complete."
      minimum_accepted_scopes ["user"]
      feature_flag :reset_copilot_live_activity_dev_tool

      error_fields

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

      def resolve(**inputs)
        user = @context[:viewer]

        success = Notifyd::Settings::RoutingSettingsService.delete(
          user.id,
          [Notifyd::Settings::MobileLiveActivityCopilotCodingAgentSettings.custom_field_group],
        )

        unless success
          raise Errors::Unprocessable.new("Failed to reset Copilot Live Activity setting in notifyd.")
        end

        {
          errors: [],
        }
      end
    end
  end
end
