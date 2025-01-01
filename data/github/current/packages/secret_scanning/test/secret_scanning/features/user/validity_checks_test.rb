# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::User
  class UserValidityChecksTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
      @user = create(:user)
      @business = create(:global_business)
      unless GitHub.enterprise?
        @emu = create(:emu)
      end
    end

    setup do
      @validity_checks_user = SecretScanning::Features::User::ValidityChecks.new(@user)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::User::ValidityChecks.new(@user).nil?
      end
    end

    context "feature_available?" do
      test "always returns false" do
        refute @validity_checks_user.feature_available?
      end
    end

    context "enabled?" do
      test "always returns false" do
        refute @validity_checks_user.enabled?
      end
    end

    context "enabled_by_enterprise?" do
      context "with a non-enterprise-managed business", skip_enterprise: true do
        test "returns false, even if the business has enabled the feature" do
          SecretScanning::Features::Business::ValidityChecks.any_instance.stubs(:enabled?).returns(true)
          refute @validity_checks_user.enabled_by_enterprise?
        end
      end

      context "with an enterprise-managed business", skip_enterprise: true do
        test "returns true if the business has enabled the feature" do
          emu_settings = SecretScanning::Features::User::ValidityChecks.new(@emu)
          refute emu_settings.enabled_by_enterprise?
          SecretScanning::Features::Business::ValidityChecks.any_instance.stubs(:enabled?).returns(true)
          assert emu_settings.enabled_by_enterprise?
        end
      end

      context "on GHES", enterprise_only: true do
        test "returns true if the global enterprise has enabled the feature" do
          refute @validity_checks_user.enabled_by_enterprise?
          SecretScanning::Features::Business::ValidityChecks.any_instance.stubs(:enabled?).returns(true)
          assert @validity_checks_user.enabled_by_enterprise?
        end
      end
    end

    context "enable" do
      test "does nothing" do
        refute @validity_checks_user.enabled?
        @validity_checks_user.enable(actor: @user)
        refute @validity_checks_user.enabled?
      end
    end

    context "disable" do
      test "does nothing" do
        refute @validity_checks_user.enabled?
        @validity_checks_user.disable(actor: @user)
        refute @validity_checks_user.enabled?
      end
    end

    context "show_security_config_ux" do
      test "returns true if vc config is enabled and security configs were available to users" do
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS].enable
        User.any_instance.stubs(:security_configurations_enabled?).returns(true)

        assert @validity_checks_user.show_security_config_ux?
      end

      test "returns false if validity checks config is not enabled" do
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS].disable
        User.any_instance.stubs(:security_configurations_enabled?).returns(true)

        refute @validity_checks_user.show_security_config_ux?
      end

      test "returns false if security configs are not available to users" do
        GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS].enable

        refute @validity_checks_user.show_security_config_ux?
      end
    end
  end
end
