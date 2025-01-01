# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Business
  class BusinessValidityChecksTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @user = create(:user)
      @business = create(:business)
      @validity_checks = SecretScanning::Features::Business::ValidityChecks.new(@business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Business::ValidityChecks.new(@business).nil?
      end
    end

    context "enterprise", enterprise_only: true do
      test "feature_available? returns false if enterprise" do
        refute @validity_checks.feature_available?
      end
    end

    context "proxima", skip_enterprise: true do
      test "feature_available? returns false" do
        on_multi_tenant_enterprise do
          refute @validity_checks.feature_available?
        end
      end
    end

    context "feature_available?", skip_enterprise: true do
      test "returns true if all conditions are met" do
        assert @validity_checks.feature_available?
      end

      test "returns false if GHAS not purchased" do
        @business.stubs(:advanced_security_purchased?).returns(false)
        refute @validity_checks.feature_available?
      end

      test "false if token scanning unavailable" do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @validity_checks.feature_available?
      end
    end

    context "enabled?", skip_enterprise: true do
      test "returns false if feature is not available" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)

        refute @validity_checks.enabled?
      end
    end

    context "enable/disable", skip_enterprise: true do
      test "returns true when feature is available, feature flag is enabled, and feature has been enabled" do
        @validity_checks.enable(actor: @user)

        assert @validity_checks.enabled?
      end

      test "returns false when feature is available feature flag is enabled, and feature has been disabled" do
        @validity_checks.enable(actor: @user)
        assert @validity_checks.enabled?
        @validity_checks.disable(actor: @user)

        refute @validity_checks.enabled?
      end
    end

    context "show_security_config_ux" do
      test "returns true" do
        assert @validity_checks.show_security_config_ux?
      end
    end
  end
end
