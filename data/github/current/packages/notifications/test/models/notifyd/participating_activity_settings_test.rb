# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class ParticipatingActivitySettingsTest < GitHub::TestCase
    RS = Notifyd::Proto::RoutingSettings
    PAS = Notifyd::ParticipatingActivitySettings

    context "#email_enabled?" do
      test "true" do
        setting = PAS.new(enabled_channels: [])
        refute setting.email_enabled?
      end

      test "false" do
        setting = PAS.new(enabled_channels: [PAS::CHANNEL_EMAIL])
        assert setting.email_enabled?
      end
    end

    context "#to_routing_setting" do
      test "email disabled" do
        setting = PAS.new(enabled_channels: [])
        routing_setting = setting.to_routing_setting

        refute setting.email_enabled?
        refute routing_setting.channels[0].enabled

        expected_routing_setting = RS::RoutingSetting.new(
          name: "notifyd_issue_participating_activity_email",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: PAS::CHANNEL_EMAIL, enabled: false)],
          filters: [
            RS::Filter.new(
              subject_type: "any",
              trigger: "any",
              reason: "any",
              match_rules: [
                RS::MatchRule.new(
                  attribute: "thread_participant_activity",
                  value: "true",
                  match_rule: "eq",
                ),
                RS::MatchRule.new(
                  attribute: "",
                  value: "participant",
                  match_rule: "in_reason_group",
                ),
              ],
            ),
          ],
          custom_fields: [
            RS::CustomField.new(name: "category", value: "user_setting_participant_activity")
          ],
        )

        assert_equal expected_routing_setting, routing_setting
      end

      test "email enabled" do
        setting = PAS.new(enabled_channels: [PAS::CHANNEL_EMAIL])
        routing_setting = setting.to_routing_setting

        assert setting.email_enabled?
        assert routing_setting.channels[0].enabled

        expected_routing_setting = RS::RoutingSetting.new(
          name: "notifyd_issue_participating_activity_email",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: PAS::CHANNEL_EMAIL, enabled: true)],
          filters: [
            RS::Filter.new(
              subject_type: "any",
              trigger: "any",
              reason: "any",
              match_rules: [
                RS::MatchRule.new(
                  attribute: "thread_participant_activity",
                  value: "true",
                  match_rule: "eq",
                ),
                RS::MatchRule.new(
                  attribute: "",
                  value: "participant",
                  match_rule: "in_reason_group",
                ),
              ],
            ),
          ],
          custom_fields: [
            RS::CustomField.new(name: "category", value: "user_setting_participant_activity"),
          ],
        )

        assert_equal expected_routing_setting, routing_setting
      end
    end
  end
end
