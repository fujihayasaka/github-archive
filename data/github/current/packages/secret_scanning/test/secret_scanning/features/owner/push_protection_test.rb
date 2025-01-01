# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Owner
  class OwnerPushProtectionTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @user = create(:user)
      @org = create(:organization)
      @org_push_protection = SecretScanning::Features::Owner::PushProtection.new(@org)
      @user_push_protection = SecretScanning::Features::Owner::PushProtection.new(@user)

      SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
      @org.stubs(:advanced_security_purchased?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Owner::PushProtection.new(@org).nil?
        refute SecretScanning::Features::Owner::PushProtection.new(@user).nil?
      end
    end

    context "feature_available?(org)" do
      test "returns true if all conditions are met" do
        assert @org_push_protection.feature_available?
      end

      test "false if token scanning unavailable" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)

        refute @org_push_protection.feature_available?
      end

      # This test also covers the case for the feature flag being disabled
      test "false if advanced security is unavailable" do
        disable_feature_flag(FeatureFlags::PUSH_PROTECTION_FOR_FPR)
        @org.stubs(:advanced_security_purchased?).returns(false)
        refute @org_push_protection.feature_available?
      end

      test "true if feature flag is enabled" do
        enable_feature_flag(FeatureFlags::PUSH_PROTECTION_FOR_FPR)
        @org.stubs(:advanced_security_purchased?).returns(false)
        assert @org_push_protection.feature_available?
      end
    end

    context "feature_available?(user)" do
      test "returns false when feature flag disabled", skip_enterprise: true do
        disable_feature_flag(FeatureFlags::PUSH_PROTECTION_FOR_FPR)
        refute @user_push_protection.feature_available?
      end

      test "returns true when feature flag enabled", skip_enterprise: true do
        enable_feature_flag(FeatureFlags::PUSH_PROTECTION_FOR_FPR)
        assert @user_push_protection.feature_available?
      end
    end

    context "enable for new repos(org)" do
      test "user enabled" do
        SecretScanning::Features::Org::PushProtection.new(@org).enable_for_new_repos(actor: @user)

        assert @org_push_protection.enabled_for_new_repos?
      end

      test "user disabled" do
        SecretScanning::Features::Org::PushProtection.new(@org).enable_for_new_repos(actor: @user)
        SecretScanning::Features::Org::PushProtection.new(@org).disable_for_new_repos(actor: @user)

        refute @org_push_protection.enabled_for_new_repos?
      end

      test "disabled if feature unavailable" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        SecretScanning::Features::Org::PushProtection.new(@org).enable_for_new_repos(actor: @user)

        refute @org_push_protection.enabled_for_new_repos?
      end

      test "disabled if feature unavailable because advanced security is not purchased" do
        disable_feature_flag(FeatureFlags::PUSH_PROTECTION_FOR_FPR)
        @org.stubs(:advanced_security_purchased?).returns(false)
        SecretScanning::Features::Org::PushProtection.new(@org).enable_for_new_repos(actor: @user)

        refute @org_push_protection.enabled_for_new_repos?
      end
    end

    context "enable for new repos(user)" do
      test "user" do
        refute @user_push_protection.enabled_for_new_repos?
      end
    end
  end
end
