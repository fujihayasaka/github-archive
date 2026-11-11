# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class AgentSessionsSettings
      RS = Notifyd::Proto::RoutingSettingsV2

      sig { params(settings: Notifications::Settings::AgentSessionsSettings).returns(RS::Setting) }
      def self.to_routing_setting(settings)
        RS::Setting.new(
          name: "agent_sessions_settings",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [
            RS::Channel.new(name: "EMAIL", enabled: settings.email),
            RS::Channel.new(name: "WEB", enabled: settings.web),
          ],
          filters: [
            RS::Filter.new(
              subject_type: "AgentSessionFinishedNotification",
              trigger: "any",
              reason: "any",
            ),
          ],
          custom_fields: custom_fields,
        )
      end

      sig { returns(T::Array[RS::CustomField]) }
      def self.custom_fields
        [
          RS::CustomField.new(
            name: "category",
            value: "agent_sessions"
          )
        ]
      end

      sig { returns(RS::CustomFieldGroup) }
      def self.custom_field_group
        RS::CustomFieldGroup.new(fields: custom_fields)
      end
    end
  end
end
