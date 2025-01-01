# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Gist
  class GistPublicScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @user = create(:user)
    end

    setup do
      @gist = create(:gist, owner: @user)
      @public_scanning = SecretScanning::Features::Gist::PublicScanning.new(@gist)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)

      enable_feature_flag(FeatureFlags::SCAN_PRIVATE_GISTS, @user)
    end

    context "feature_available?" do
      test "returns true if all conditions are met", skip_enterprise: true do
        assert @public_scanning.feature_available?
      end

      test "false on GHES", enterprise_only: true do
        refute @public_scanning.feature_available?
      end

      test "false if global config disabled" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

        refute @public_scanning.feature_available?
      end
    end

    context "enabled?" do
      test "true for public gists", skip_enterprise: true do
        @gist.stubs(:public?).returns(true)
        assert @public_scanning.enabled?
      end

      test "false for public gists on GHES", enterprise_only: true do
        @gist.stubs(:public?).returns(true)
        refute @public_scanning.enabled?
      end

      test "true for private gists if feature flag is enabled", skip_enterprise: true do
        gist = create(:gist, owner: @user, public: false)
        feature = SecretScanning::Features::Gist::PublicScanning.new(gist)

        assert feature.enabled?
      end

      test "false for private gists" do
        disable_feature_flag(FeatureFlags::SCAN_PRIVATE_GISTS, @user)

        @gist.stubs(:public?).returns(false)
        refute @public_scanning.enabled?
      end

      test "false if feature unavailable" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
        @gist.stubs(:public?).returns(true)
        refute @public_scanning.enabled?
      end
    end
  end
end
