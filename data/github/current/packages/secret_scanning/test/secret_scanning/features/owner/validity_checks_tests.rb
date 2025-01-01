# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Owner
  class OwnerValidityChecksTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @user = create(:user)
      @org = create(:organization)
      @business = create(:business)
      @biz_validity_checks = SecretScanning::Features::Owner::ValidityChecks.new(@business)
      @org_validity_checks = SecretScanning::Features::Owner::ValidityChecks.new(@org)
      @user_validity_checks = SecretScanning::Features::Owner::ValidityChecks.new(@user)

      SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
      @org.stubs(:advanced_security_purchased?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Owner::ValidityChecks.new(@business).nil?
        refute SecretScanning::Features::Owner::ValidityChecks.new(@org).nil?
        refute SecretScanning::Features::Owner::ValidityChecks.new(@user).nil?
      end
    end

    context "feature_available? (biz)" do
      test "feature_available? returns false" do
        refute @biz_validity_checks.feature_available?
      end
    end

    context "feature_available? (org)", skip_enterprise: true do
      test "returns true if all conditions are met" do
        assert @org_validity_checks.feature_available?
      end

      test "false if token scanning unavailable" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)

        refute @org_validity_checks.feature_available?
      end

      test "false if advanced security is unavailable" do
        @org.stubs(:advanced_security_purchased?).returns(false)
        refute @org_validity_checks.feature_available?
      end

      test "false if enterprise mode" do
        GitHub.stubs("single_or_multi_tenant_enterprise?").returns(true)
        refute @org_validity_checks.feature_available?
      end
    end

    context "feature_available? (users)" do
      test "always returns false" do
        refute @user_validity_checks.feature_available?
      end
    end

    context "show_security_config_ux" do
      test "returns true if config and vc config is enabled" do
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS].enable

        assert @org_validity_checks.show_security_config_ux?
      end

      test "returns false if validity checks config is not enabled" do
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS].disable

        refute @org_validity_checks.show_security_config_ux?
      end

      test "returns false if security config is not enabled" do
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS].enable

        refute @org_validity_checks.show_security_config_ux?
      end
    end
  end
end
