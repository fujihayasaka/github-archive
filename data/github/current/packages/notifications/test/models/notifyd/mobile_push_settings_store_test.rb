# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class MobilePushSettingsStoreTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
    end

    context "with the feature enabled" do
      test "#get" do
        enable_feature_flag(:notifyd_mobile_push_ci_activity, @user)
        disable_feature_flag(:notifyd_mobile_push_watched_activity)
        ci_resp = Notifyd::Proto::RoutingSettings::GetResponse.new(
          routing_setting: [MobilePushSettings.new(ci_activity: true).to_ci_activity_routing_setting]
        )
        watched_resp = Notifyd::Proto::RoutingSettings::GetResponse.new(
          routing_setting: [MobilePushSettings.new(releases: true).to_releases_routing_setting]
        )

        RoutingSettingsService.any_instance.expects(:get).returns(ci_resp)

        settings = MobilePushSettingsStore.new(user: @user).get

        assert settings.ci_activity
        refute settings.ci_failed_only
        refute settings.releases
      end

      test "#get for watched activty" do
        disable_feature_flag(:notifyd_mobile_push_ci_activity)
        enable_feature_flag(:notifyd_mobile_push_watched_activity, @user)
        response = Notifyd::Proto::RoutingSettings::GetResponse.new(
          routing_setting: [MobilePushSettings.new(releases: true).to_releases_routing_setting]
        )
        RoutingSettingsService.any_instance.expects(:get).returns(response)

        settings = MobilePushSettingsStore.new(user: @user).get

        refute settings.ci_activity
        refute settings.ci_failed_only
        assert settings.releases
      end

      test "#save when the settings is clean and the flags are mixed" do
        enable_feature_flag(:notifyd_mobile_push_ci_activity, @user)
        disable_feature_flag(:notifyd_mobile_push_watched_activity)
        settings = MobilePushSettings.new

        assert MobilePushSettingsStore.new(user: @user).save(settings: settings)
      end

      test "#save when the settings is dirty and the flags are mixed" do
        enable_feature_flag(:notifyd_mobile_push_ci_activity, @user)
        disable_feature_flag(:notifyd_mobile_push_watched_activity)
        settings = MobilePushSettings.new
        settings.ci_activity = true
        RoutingSettingsService.any_instance
          .expects(:save)
          .with([settings.to_ci_activity_routing_setting])
          .returns(true)

        assert MobilePushSettingsStore.new(user: @user).save(settings: settings)
      end

      test "#save when the settings is dirty and both flags are on" do
        enable_feature_flag(:notifyd_mobile_push_ci_activity, @user)
        enable_feature_flag(:notifyd_mobile_push_watched_activity, @user)
        settings = MobilePushSettings.new
        settings.ci_activity = true
        RoutingSettingsService.any_instance
          .expects(:save)
          .with([settings.to_ci_activity_routing_setting, settings.to_releases_routing_setting])
          .returns(true)

        assert MobilePushSettingsStore.new(user: @user).save(settings: settings)
      end
    end

    context "with the feature disabled" do
      test "#get" do
        disable_feature_flag(:notifyd_mobile_push_ci_activity)
        disable_feature_flag(:notifyd_mobile_push_watched_activity)

        settings = MobilePushSettingsStore.new(user: @user).get
        refute settings.ci_activity
        refute settings.ci_failed_only
        refute settings.releases
      end

      test "#save" do
        disable_feature_flag(:notifyd_mobile_push_ci_activity)
        disable_feature_flag(:notifyd_mobile_push_watched_activity)

        settings = MobilePushSettings.new
        assert MobilePushSettingsStore.new(user: @user).save(settings: settings)
      end
    end
  end
end
