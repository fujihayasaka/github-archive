# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class SelfActivityEmailSettings
      RS = Notifyd::Proto::RoutingSettingsV2

      sig { params(user_id: Integer).returns(RS::Setting) }
      def self.to_routing_setting(user_id:)
        RS::Setting.new(
          name: "self_activity_email_settings",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(
            name: "EMAIL",
            enabled: true,
          )],
          filters: [RS::Filter.new(
            subject_type: "any",
            trigger: "any",
            reason: "any",
            match_rules: [RS::MatchRule.new(
              attribute: "actor_id",
              value: user_id.to_s,
              match_rule: "eq",
            )]
          )],
          custom_fields: custom_fields
        )
      end

      sig { returns(T::Array[RS::CustomField]) }
      def self.custom_fields
        [RS::CustomField.new(name: "category", value: "user_setting_self_activity_email")]
      end

      sig { returns(RS::CustomFieldGroup) }
      def self.custom_field_group
        RS::CustomFieldGroup.new(fields: custom_fields)
      end
    end
  end
end
