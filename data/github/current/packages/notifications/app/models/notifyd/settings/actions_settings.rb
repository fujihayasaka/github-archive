# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class ActionsSettings
      RS = Notifyd::Proto::RoutingSettingsV2

      sig { params(settings: Notifications::Settings::ActionsSettings).returns(RS::Setting) }
      def self.to_routing_setting(settings)
        match_rules = []
        if settings.failures
          match_rules << RS::MatchRule.new(attribute: "failed", value: "true", match_rule: "eq")
        end

        RS::Setting.new(
          name: "actions_settings",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [
            RS::Channel.new(name: "EMAIL", enabled: settings.email),
            RS::Channel.new(name: "WEB", enabled: settings.web),
          ],
          filters: [
            RS::Filter.new(
              subject_type: "any",
              trigger: "any",
              reason: "ci_activity",
              match_rules: match_rules,
            ),
            RS::Filter.new(
              subject_type: "any",
              trigger: "any",
              reason: "approval_requested",
            ),
          ],
          custom_fields: custom_fields
        )
      end

      sig { returns(T::Array[RS::CustomField]) }
      def self.custom_fields
        [
          RS::CustomField.new(
            name: "delivery_group",
            value: "ci_activity"
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
