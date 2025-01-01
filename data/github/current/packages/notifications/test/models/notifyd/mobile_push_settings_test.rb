# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class MobilePushSettingsTest < GitHub::TestCase
    RS = Notifyd::Proto::RoutingSettings

    context "#ci_activity=" do
      test "disables ci_failed_only when it is disabled" do
        setting = MobilePushSettings.new(ci_activity: true, ci_failed_only: true)
        setting.ci_activity = false

        refute setting.ci_failed_only
        assert_predicate setting, :dirty?
      end

      test "does nothing when it is the same value" do
        setting = MobilePushSettings.new(ci_activity: false)
        setting.ci_activity = false

        refute_predicate setting, :dirty?
      end
    end

    context "#ci_failed_only=" do
      test "does nothing if ci_activity is disabled" do
        setting = MobilePushSettings.new(ci_activity: false, ci_failed_only: false)
        setting.ci_failed_only = true

        refute setting.ci_failed_only
        refute_predicate setting, :dirty?
      end

      test "enables only failed CI if ci_activity is enabled" do
        setting = MobilePushSettings.new(ci_activity: true)
        setting.ci_failed_only = true

        assert setting.ci_failed_only
        assert_predicate setting, :dirty?
      end
    end

    context "#to_routing_setting" do
      test "all disabled" do
        setting = MobilePushSettings.new(ci_activity: false, ci_failed_only: false, releases: false)
        ci_routing_setting = setting.to_ci_activity_routing_setting
        releases_routing_setting = setting.to_releases_routing_setting

        refute ci_routing_setting.channels[0].enabled
        assert_predicate ci_routing_setting.filters[0].match_rules, :empty?
        refute releases_routing_setting.channels[0].enabled
      end

      test "all enabled" do
        setting = MobilePushSettings.new(ci_activity: true, ci_failed_only: true, releases: true)
        ci_routing_setting = setting.to_ci_activity_routing_setting
        releases_routing_setting = setting.to_releases_routing_setting

        assert ci_routing_setting.channels[0].enabled
        assert_equal ci_routing_setting.filters[0].match_rules[0].value, "true"
        assert releases_routing_setting.channels[0].enabled
      end

      test "enabled but for all notifications" do
        setting = MobilePushSettings.new(ci_activity: true, ci_failed_only: false)
        routing_setting = setting.to_ci_activity_routing_setting

        assert routing_setting.channels[0].enabled
        assert_predicate routing_setting.filters[0].match_rules, :empty?
      end
    end

    context ".new_from_routing_setting on different or none delivery group" do
      test "for an empty routing settings all is false" do
        routing_setting = RS::RoutingSetting.new
        routing_setting.channels << RS::Channel.new(name: "PUSH", enabled: true)
        settings = MobilePushSettings.new_from_routing_setting([routing_setting])

        refute settings.ci_activity
        refute settings.ci_failed_only
        refute settings.releases
      end

      test "all disabled even when channel is enabled" do
        routing_setting = RS::RoutingSetting.new
        routing_setting.custom_fields << RS::CustomField.new(name: "mobile_delivery_group", value: "foo")
        routing_setting.channels << RS::Channel.new(name: "PUSH", enabled: true)
        settings = MobilePushSettings.new_from_routing_setting([routing_setting])

        refute settings.ci_activity
        refute settings.ci_failed_only
        refute settings.releases
      end

      test "all disabled when no channel" do
        ci_routing_setting = RS::RoutingSetting.new
        ci_routing_setting.custom_fields << RS::CustomField.new(name: "mobile_delivery_group", value: "ci_activity")

        releases_routing_setting = RS::RoutingSetting.new
        releases_routing_setting.custom_fields << RS::CustomField.new(name: "mobile_delivery_group", value: "watched_activity")
        settings = MobilePushSettings.new_from_routing_setting([ci_routing_setting, releases_routing_setting])

        refute settings.ci_activity
        refute settings.ci_failed_only
        refute settings.releases
      end
    end

    context ".new_routing_setting on same delivery group" do
      test "enabled if channel is enabled" do
        routing_setting = RS::RoutingSetting.new
        routing_setting.custom_fields << RS::CustomField.new(name: "mobile_delivery_group", value: "ci_activity")
        routing_setting.channels << RS::Channel.new(name: "PUSH", enabled: true)
        settings = MobilePushSettings.new_from_routing_setting([routing_setting])

        assert settings.ci_activity
        refute settings.ci_failed_only
      end

      test "failed only is enabled if filter present" do
        ci_routing_setting = RS::RoutingSetting.new
        ci_routing_setting.custom_fields << RS::CustomField.new(name: "mobile_delivery_group", value: "ci_activity")
        ci_routing_setting.channels << RS::Channel.new(name: "PUSH", enabled: true)
        ci_routing_setting.filters << RS::Filter.new(match_rules: [
          RS::MatchRule.new(match_rule: "eq", attribute: "failed", value: "true")
        ])

        releases_routing_setting = RS::RoutingSetting.new
        releases_routing_setting.custom_fields << RS::CustomField.new(name: "category", value: "user_setting_watcher_activity")
        releases_routing_setting.custom_fields << RS::CustomField.new(name: "scenario", value: "user_settings")

        releases_routing_setting.channels << RS::Channel.new(name: "PUSH", enabled: true)

        settings = MobilePushSettings.new_from_routing_setting([ci_routing_setting, releases_routing_setting])

        assert settings.ci_activity
        assert settings.ci_failed_only
        assert settings.releases
      end

      test "failed only is only enabled if channel is also enabled" do
        ci_routing_setting = RS::RoutingSetting.new
        ci_routing_setting.custom_fields << RS::CustomField.new(name: "mobile_delivery_group", value: "ci_activity")
        ci_routing_setting.channels << RS::Channel.new(name: "PUSH", enabled: false)
        ci_routing_setting.filters << RS::Filter.new(match_rules: [
          RS::MatchRule.new(match_rule: "eq", attribute: "failed", value: "true")
        ])

        releases_routing_setting = RS::RoutingSetting.new
        releases_routing_setting.custom_fields << RS::CustomField.new(name: "category", value: "user_setting_watcher_activity")
        releases_routing_setting.custom_fields << RS::CustomField.new(name: "scenario", value: "user_settings")
        releases_routing_setting.channels << RS::Channel.new(name: "PUSH", enabled: false)

        settings = MobilePushSettings.new_from_routing_setting([ci_routing_setting, releases_routing_setting])

        refute settings.ci_activity
        refute settings.ci_failed_only
        refute settings.releases
      end
    end
  end
end
