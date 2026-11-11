# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class MobileLiveActivityCopilotCodingAgentSettings
      RS = Notifyd::Proto::RoutingSettingsV2

      sig { params(settings: Notifications::Settings::MobileLiveActivityCopilotCodingAgentSettings).returns(T::Array[RS::Setting]) }
      def self.to_routing_settings(settings)
        routing_settings = [
          RS::Setting.new(
            name: "mobile_live_activity_copilot_coding_agent_settings",
            topics: [RS::Topic.new(type: "any", value: "any")],
            channels: [RS::Channel.new(name: "PUSH", enabled: settings.push)],
            filters: [
              RS::Filter.new(
                subject_type: "any",
                trigger: "any",
                reason: "live_activity_copilot_coding_agent",
              ),
            ],
            custom_fields: custom_fields,
          )
        ]
        if settings.push
          routing_settings << RS::Setting.new(
            name: "mobile_live_activity_copilot_coding_agent_mute_settings",
            topics: [RS::Topic.new(type: "any", value: "any")],
            channels: [RS::Channel.new(name: "PUSH", enabled: false)],
            filters: [
              RS::Filter.new(
                subject_type: "IssueEvent",
                trigger: "any",
                reason: "any",
                match_rules: [
                  RS::MatchRule.new(
                    attribute: "actor_is_agentic_app",
                    value: "true",
                    match_rule: "eq",
                  ),
                  RS::MatchRule.new(
                    attribute: "thread_type",
                    value: "pull_request",
                    match_rule: "eq",
                  )
                ],
              ),
            ],
            custom_fields: custom_fields,
          )
        end
        routing_settings
      end

      sig { returns(T::Array[RS::CustomField]) }
      def self.custom_fields
        [RS::CustomField.new(name: "category", value: "user_setting_live_activity_copilot_coding_agent")]
      end

      sig { returns(RS::CustomFieldGroup) }
      def self.custom_field_group
        RS::CustomFieldGroup.new(fields: custom_fields)
      end
    end
  end
end
