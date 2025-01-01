# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Org
  class OrgPublicScanningTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      business = create(:business)
      @org = create(:business_plus_org, business: business)
      @user = create(:user)
    end

    setup do
      @public_scanning = SecretScanning::Features::Org::PublicScanning.new(@org)
      @token_scanning = SecretScanning::Features::Org::TokenScanning.new(@org)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Org::PublicScanning.new(@org).nil?
      end

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

    context "stafftools_available?" do
      test "returns true if all conditions are met", skip_enterprise: true do
        assert @public_scanning.stafftools_available?
      end

      test "false on GHES", enterprise_only: true do
        refute @public_scanning.stafftools_available?
      end

      test "false if global config disabled" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

        refute @public_scanning.stafftools_available?
      end
    end

    context "enabled?" do
      test "true", skip_enterprise: true do
        assert @public_scanning.enabled?
      end

      test "false on GHES", enterprise_only: true do
        refute @public_scanning.enabled?
      end

      test "false if feature unavailable" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
        refute @public_scanning.enabled?
      end
    end
  end
end
