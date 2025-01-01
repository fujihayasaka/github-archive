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
        Flipper[:notifyd_mobile_push_ci_activity].enable(@user)
        Flipper[:notifyd_mobile_push_watched_activity].disable
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
        Flipper[:notifyd_mobile_push_ci_activity].disable
        Flipper[:notifyd_mobile_push_watched_activity].enable(@user)
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
        Flipper[:notifyd_mobile_push_ci_activity].enable(@user)
        Flipper[:notifyd_mobile_push_watched_activity].disable
        settings = MobilePushSettings.new

        assert MobilePushSettingsStore.new(user: @user).save(settings: settings)
      end

      test "#save when the settings is dirty and the flags are mixed" do
        Flipper[:notifyd_mobile_push_ci_activity].enable(@user)
        Flipper[:notifyd_mobile_push_watched_activity].disable
        settings = MobilePushSettings.new
        settings.ci_activity = true
        RoutingSettingsService.any_instance
          .expects(:save)
          .with([settings.to_ci_activity_routing_setting])
          .returns(true)

        assert MobilePushSettingsStore.new(user: @user).save(settings: settings)
      end

      test "#save when the settings is dirty and both flags are on" do
        Flipper[:notifyd_mobile_push_ci_activity].enable(@user)
        Flipper[:notifyd_mobile_push_watched_activity].enable(@user)
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
        Flipper[:notifyd_mobile_push_ci_activity].disable
        Flipper[:notifyd_mobile_push_watched_activity].disable

        settings = MobilePushSettingsStore.new(user: @user).get
        refute settings.ci_activity
        refute settings.ci_failed_only
        refute settings.releases
      end

      test "#save" do
        Flipper[:notifyd_mobile_push_ci_activity].disable
        Flipper[:notifyd_mobile_push_watched_activity].disable

        settings = MobilePushSettings.new
        assert MobilePushSettingsStore.new(user: @user).save(settings: settings)
      end
    end
  end
end
