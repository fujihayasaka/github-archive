# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class IssueCommentsEmailSettings
      RS = Notifyd::Proto::RoutingSettingsV2

      sig { returns(RS::Setting) }
      def self.to_routing_setting
        RS::Setting.new(
          name: "issue_comments_email_settings",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: "EMAIL", enabled: false)],
          filters: [
            RS::Filter.new(
              subject_type: "IssueComment",
              trigger: "any",
              reason: "any",
              match_rules: [
                RS::MatchRule.new(
                  attribute: "",
                  value: "notify_muted",
                  match_rule: "not_in_reason_group",
                )
              ]
            )
          ],
          custom_fields: custom_fields
        )
      end

      sig { returns(T::Array[RS::CustomField]) }
      def self.custom_fields
        [
          RS::CustomField.new(
            name: "category",
            value: "user_setting_issue_comments_email",
          )
        ]
      end
    end
  end
end
