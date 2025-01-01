# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class WatcherActivitySettingsTest < GitHub::TestCase
    RS = Notifyd::Proto::RoutingSettings
    WAS = Notifyd::WatcherActivitySettings

    context "#email_enabled?" do
      test "true" do
        setting = WAS.new(enabled_channels: [])
        refute setting.email_enabled?
      end

      test "false" do
        setting = WAS.new(enabled_channels: [WAS::CHANNEL_EMAIL])
        assert setting.email_enabled?
      end
    end

    context "#to_routing_setting" do
      test "email disabled" do
        setting = WAS.new(enabled_channels: [])
        routing_setting = setting.to_routing_setting

        refute setting.email_enabled?
        refute routing_setting.channels[0].enabled

        expected_routing_setting = RS::RoutingSetting.new(
          name: "notifyd_watcher_activity_setting",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: WAS::CHANNEL_EMAIL, enabled: false)],
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
          custom_fields: [
            RS::CustomField.new(name: "category", value: "user_setting_watcher_activity"),
          ],
        )

        assert_equal expected_routing_setting, routing_setting
      end

      test "email enabled" do
        setting = WAS.new(enabled_channels: [WAS::CHANNEL_EMAIL])
        routing_setting = setting.to_routing_setting

        assert setting.email_enabled?
        assert routing_setting.channels[0].enabled

        expected_routing_setting = RS::RoutingSetting.new(
          name: "notifyd_watcher_activity_setting",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: WAS::CHANNEL_EMAIL, enabled: true)],
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
          custom_fields: [
            RS::CustomField.new(name: "category", value: "user_setting_watcher_activity"),
          ],
        )
        assert_equal expected_routing_setting, routing_setting
      end
    end
  end
end
