# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    # NOTE(abeaumont): Only ci_activity is currently migrated to notifyd,
    # approval_requested is not yet supported.
    class MobileActionsSettings
      RS = Notifyd::Proto::RoutingSettingsV2

      sig { params(settings: Notifications::Settings::MobileActionsSettings).returns(RS::Setting) }
      def self.to_routing_setting(settings)
        match_rules = []
        if settings.failures
          match_rules << RS::MatchRule.new(attribute: "failed", value: "true", match_rule: "eq")
        end

        RS::Setting.new(
          name: "mobile_actions_settings",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: "PUSH", enabled: settings.push)],
          filters: [RS::Filter.new(subject_type: "any", trigger: "any", reason: "ci_activity", match_rules:)],
          custom_fields: custom_fields,
        )
      end

      sig { returns(T::Array[RS::CustomField]) }
      def self.custom_fields
        [
          RS::CustomField.new(
            name: "mobile_delivery_group",
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
