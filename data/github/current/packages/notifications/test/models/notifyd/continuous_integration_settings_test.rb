# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class ContinuousIntegrationSettingsTest < GitHub::TestCase
    RS = Notifyd::Proto::RoutingSettings
    CIS = Notifyd::ContinuousIntegrationSettings

    context "#to_routing_setting" do
      test "email enabled" do
        expected_settings = RS::RoutingSetting.new(
          name: "CI Activity",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: "EMAIL", enabled: true)],
          custom_fields: [RS::CustomField.new(name: "delivery_group", value: "ci_activity")],
          filters: [
            RS::Filter.new(subject_type: "any", trigger: "any", reason: "ci_activity"),
            RS::Filter.new(subject_type: "any", trigger: "any", reason: "approval_requested"),
          ],
        )

        actual_settings = ContinuousIntegrationSettings
          .new(continuous_integration_email: true, continuous_integration_failures_only: false)
          .to_routing_setting

        assert_equal expected_settings, actual_settings
      end

      test "email disabled" do
        expected_settings = RS::RoutingSetting.new(
          name: "CI Activity",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: "EMAIL", enabled: false)],
          custom_fields: [RS::CustomField.new(name: "delivery_group", value: "ci_activity")],
          filters: [
            RS::Filter.new(subject_type: "any", trigger: "any", reason: "ci_activity"),
            RS::Filter.new(subject_type: "any", trigger: "any", reason: "approval_requested"),
          ],
        )
        actual_settings = ContinuousIntegrationSettings
          .new(continuous_integration_email: false, continuous_integration_failures_only: false)
          .to_routing_setting
        assert_equal expected_settings, actual_settings
      end

      test "email enabled, only failures" do
        expected_settings = RS::RoutingSetting.new(
          name: "CI Activity",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: "EMAIL", enabled: true)],
          custom_fields: [RS::CustomField.new(name: "delivery_group", value: "ci_activity")],
          filters: [
            RS::Filter.new(
              subject_type: "any",
              trigger: "any",
              reason: "ci_activity",
              match_rules: [
                RS::MatchRule.new(
                  attribute: "failed",
                  value: "true",
                  match_rule: "eq",
               ),
              ],
            ),
            RS::Filter.new(subject_type: "any", trigger: "any", reason: "approval_requested"),
          ],
        )
        actual_settings = ContinuousIntegrationSettings
          .new(continuous_integration_email: true, continuous_integration_failures_only: true)
          .to_routing_setting
        assert_equal expected_settings, actual_settings
      end

      test "email disabled, only failures" do
        expected_settings = RS::RoutingSetting.new(
          name: "CI Activity",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: "EMAIL", enabled: false)],
          custom_fields: [RS::CustomField.new(name: "delivery_group", value: "ci_activity")],
          filters: [
            RS::Filter.new(
              subject_type: "any",
              trigger: "any",
              reason: "ci_activity",
              match_rules: [
                RS::MatchRule.new(
                  attribute: "failed",
                  value: "true",
                  match_rule: "eq",
                ),
              ],
            ),
            RS::Filter.new(subject_type: "any", trigger: "any", reason: "approval_requested"),
          ],
        )
        actual_settings = ContinuousIntegrationSettings
          .new(continuous_integration_email: false, continuous_integration_failures_only: true)
          .to_routing_setting
        assert_equal expected_settings, actual_settings
      end
    end
  end
end
