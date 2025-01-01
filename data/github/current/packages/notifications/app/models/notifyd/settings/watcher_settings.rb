# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class WatcherSettings
      RS = Notifyd::Proto::RoutingSettingsV2

      sig { params(settings: Notifications::Settings::WatcherSettings).returns(RS::Setting) }
      def self.to_routing_setting(settings)
        RS::Setting.new(
          name: "watcher_settings",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [
            RS::Channel.new(name: "EMAIL", enabled: settings.email),
            RS::Channel.new(name: "WEB", enabled: settings.web)
          ],
          filters: [
            RS::Filter.new(
              subject_type: "any",
              trigger: "any",
              reason: "any",
              match_rules: [
                RS::MatchRule.new(
                  attribute: "watch_activity",
                  value: "true",
                  match_rule: "eq",
                ),
                RS::MatchRule.new(
                  value: "participant",
                  match_rule: "not_in_reason_group",
                ),
              ],
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
            value: "user_setting_watcher_activity",
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
