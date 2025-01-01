# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::User
  class UserPushProtectionTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @user = create(:user)
      @repo = create(:repository)
      @push_protection = SecretScanning::Features::User::PushProtection.new(@user)
      @repo_push_protection = SecretScanning::Features::Repo::PushProtection.new(@repo)
      @user.config.delete(SecretScanning::Features::User::PushProtection::CONFIG_KEY_ENABLED_FOR_NEW_REPOS, @user)
      @repo.owner.stubs(:advanced_security_purchased?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_FPR].enable
      GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_USERS_OPT_OUT].disable
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

      ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(true)
      unless GitHub.enterprise?
        @emu_user = create :emu, :owner
        @emu_business = @emu_user.enterprise_managed_business
      end
    end

    context "initialize" do
      test "good input" do
        refute @push_protection.nil?
      end
    end

    context "feature_available?" do
      test "false if config is not set" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
        refute @push_protection.feature_available?
      end

      test "ghes - false if GHAS is not available for the user", enterprise_only: true do
        ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(false)
        refute @push_protection.feature_available?
      end

      test "ghes - true if GHAS is available for the user", enterprise_only: true do
        assert @push_protection.feature_available?
      end

      test "false if not available for free public users", skip_enterprise: true do
        ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(false)
        GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_FPR].disable
        refute @push_protection.feature_available?
      end

      test "true if available for free public users", skip_enterprise: true do
        assert @push_protection.feature_available?
      end

      test "false if GHAS is not available for the user" do
        ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(false)
        GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_FPR].disable
        on_multi_tenant_enterprise(tenant: @emu_business) do
          refute @push_protection.feature_available?
        end
      end

      test "true if GHAS is available for the user" do
        GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_FPR].disable
        on_multi_tenant_enterprise(tenant: @emu_business) do
          assert @push_protection.feature_available?
        end
      end
    end

    context "enabled_for_new_repos?" do
      test "cannot enable/disable push protection for new repos if feature flag is off", skip_enterprise: true do
        ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(false)
        GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_FPR].disable
        refute @push_protection.enabled_for_new_repos?
        @push_protection.enable_for_new_repos(actor: @user)
        refute @push_protection.enabled_for_new_repos?
      end

      test "enable/disable push protection for new repos on dotcom" do
        refute @push_protection.enabled_for_new_repos?

        @push_protection.enable_for_new_repos(actor: @user)
        assert @push_protection.enabled_for_new_repos?

        @push_protection.disable_for_new_repos(actor: @user)
        refute @push_protection.enabled_for_new_repos?
      end
    end

    context "enabled_for_user_anywhere?" do
      test "cannot enable/disable push protection for anywhere if feature flag is off", skip_enterprise: true do
        ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(false)
        GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_FPR].disable
        refute @push_protection.enabled?
        @push_protection.enable(actor: @user)
        refute @push_protection.enabled?
      end

      test "enable/disable push protection for anywhere on dotcom" do
        refute @push_protection.enabled?

        @push_protection.enable(actor: @user)
        assert @push_protection.enabled?

        @push_protection.disable(actor: @user)
        refute @push_protection.enabled?
      end

      test "push protection on by default when flag is on", skip_enterprise: true do
        GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_USERS_OPT_OUT].enable(@user)
        assert @push_protection.enabled?

        # Verify that flag back off will restore things to their former state
        GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_USERS_OPT_OUT].disable(@user)

        refute @push_protection.enabled?
      end

      test "push protection on by default when flag is on, disable respected", skip_enterprise: true do
        GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_USERS_OPT_OUT].enable(@user)
        assert @push_protection.enabled?

        @push_protection.disable(actor: @user)
        refute @push_protection.enabled?
      end

      test "push protection disabled before FF on, respected after FF on", skip_enterprise: true do
        @push_protection.enable(actor: @user)
        assert @push_protection.enabled?

        @push_protection.disable(actor: @user)
        GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_USERS_OPT_OUT].enable

        refute @push_protection.enabled?

        @push_protection.enable(actor: @user)
        assert @push_protection.enabled?
      end
    end

    context "has_user_bypass_experience?" do
      test "returns true if user push protection is enabled and repo push protection is disabled" do
        @push_protection.enable(actor: @user)
        @repo_push_protection.disable(actor: @user)
        assert @push_protection.has_user_bypass_experience?(@repo)
      end

      test "returns false if user push protection is enabled and repo push protection is enabled" do
        @push_protection.enable(actor: @user)
        @repo_push_protection.enable(actor: @user)
        refute @push_protection.has_user_bypass_experience?(@repo)
      end

      test "returns false if user push protection is disabled and repo push protection is disabled" do
        @push_protection.disable(actor: @user)
        @repo_push_protection.disable(actor: @user)
        refute @push_protection.has_user_bypass_experience?(@repo)
      end

      test "returns false if user push protection is disabled and repo push protection is enabled" do
        @push_protection.disable(actor: @user)
        @repo_push_protection.enable(actor: @user)
        refute @push_protection.has_user_bypass_experience?(@repo)
      end
    end
  end
end
