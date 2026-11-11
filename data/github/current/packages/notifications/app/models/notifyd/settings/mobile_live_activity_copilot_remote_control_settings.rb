# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class MobileLiveActivityCopilotRemoteControlSettings
      RS = Notifyd::Proto::RoutingSettingsV2

      sig { params(settings: Notifications::Settings::MobileLiveActivityCopilotRemoteControlSettings).returns(T::Array[RS::Setting]) }
      def self.to_routing_settings(settings)
        [
          RS::Setting.new(
            name: "mobile_live_activity_copilot_remote_control_settings",
            topics: [RS::Topic.new(type: "any", value: "any")],
            channels: [RS::Channel.new(name: "PUSH", enabled: settings.push)],
            filters: [
              RS::Filter.new(
                subject_type: "any",
                trigger: "any",
                reason: "live_activity_copilot_remote_control",
              ),
            ],
            custom_fields: custom_fields,
          )
        ]
      end

      sig { returns(T::Array[RS::CustomField]) }
      def self.custom_fields
        [RS::CustomField.new(name: "category", value: "user_setting_live_activity_copilot_remote_control")]
      end

      sig { returns(RS::CustomFieldGroup) }
      def self.custom_field_group
        RS::CustomFieldGroup.new(fields: custom_fields)
      end
    end
  end
end
