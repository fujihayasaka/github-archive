# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Org
  class OrgValidityChecksTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @user = create(:user)
      @business = create(:business)
      @org = create(:organization, business: @business)
      @validity_checks = SecretScanning::Features::Org::ValidityChecks.new(@org)
      @business_validity_checks = SecretScanning::Features::Business::ValidityChecks.new(@business)
      SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
      @org.stubs(:advanced_security_purchased?).returns(true)
      @business.stubs(:advanced_security_purchased?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Org::ValidityChecks.new(@org).nil?
      end
    end

    context "enterprise", enterprise_only: true do
      test "feature_available? returns false" do
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

      test "false if token scanning unavailable" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)

        refute @validity_checks.feature_available?
      end

      test "false if advanced security is unavailable" do
        @org.stubs(:advanced_security_purchased?).returns(false)
        refute @validity_checks.feature_available?
      end

      test "false if enterprise mode" do
        GitHub.stubs("single_or_multi_tenant_enterprise?").returns(true)
        refute @validity_checks.feature_available?
      end
    end

    context "enabled_by_owner?", skip_enterprise: true do
      test "returns true without security config if validity checks have been enabled by the business that owns the org" do
        @validity_checks.stubs(:show_security_config_ux?).returns(false)
        @validity_checks.disable(actor: @user)
        refute @validity_checks.enabled?

        @business_validity_checks.enable(actor: @user)
        assert @validity_checks.enabled?
        assert @validity_checks.enabled_by_owner?
      end

      test "returns false with security config even if validity checks have been enabled by the business that owns the org" do
        @validity_checks.stubs(:show_security_config_ux?).returns(true)
        @validity_checks.disable(actor: @user)
        refute @validity_checks.enabled?

        @business_validity_checks.enable(actor: @user)
        refute @validity_checks.enabled?
        refute @validity_checks.enabled_by_owner?
      end

      test "returns false if not enabled by owner" do
        @validity_checks.disable(actor: @user)
        refute @validity_checks.enabled?

        @validity_checks.enable(actor: @user)
        assert @validity_checks.enabled?
        refute @validity_checks.enabled_by_owner?
      end
    end

    context "enabled", skip_enterprise: true do
      test "returns false if feature is not available" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)

        refute @validity_checks.enabled?
      end

      test "returns true without security config if validity checks are enabled for the business but disabled for the org" do
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        @validity_checks.disable(actor: @user)
        refute @validity_checks.enabled?

        @business_validity_checks.enable(actor: @user)
        assert @validity_checks.enabled?
      end

      test "returns true without security config if validity checks are disabled for the business but enabled for the org" do
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(false)
        @validity_checks.disable(actor: @user)
        refute @validity_checks.enabled?

        @business_validity_checks.disable(actor: @user)
        refute @validity_checks.enabled?

        @validity_checks.enable(actor: @user)
        assert @validity_checks.enabled?
      end

      test "returns false with security config even if validity checks were enabled for the business" do
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:show_security_config_ux?).returns(true)
        @validity_checks.disable(actor: @user)
        refute @validity_checks.enabled?

        @business_validity_checks.enable(actor: @user)
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
