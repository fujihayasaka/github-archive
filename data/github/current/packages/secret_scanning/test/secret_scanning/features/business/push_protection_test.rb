# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Business
  class BusinessPushProtectionTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @user = create(:user)
      @business = create(:business)
      @push_protection = SecretScanning::Features::Business::PushProtection.new(@business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Business::PushProtection.new(@business).nil?
      end
    end

    context "feature_available?" do
      test "returns true if all conditions are met" do
        assert @push_protection.feature_available?
      end

      # This test also covers the case for the feature flag being disabled
      test "returns false if GHAS not purchased" do
        disable_feature_flag(FeatureFlags::PUSH_PROTECTION_FOR_FPR)
        @business.stubs(:advanced_security_purchased?).returns(false)
        refute @push_protection.feature_available?
      end

      test "false if token scanning unavailable" do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @push_protection.feature_available?
      end

      test "true if feature flag is enabled" do
        enable_feature_flag(FeatureFlags::PUSH_PROTECTION_FOR_FPR)
        @business.stubs(:advanced_security_purchased?).returns(false)
        assert @push_protection.feature_available?
      end
    end

    context "enable for new repos" do
      test "user enabled" do
        @push_protection.enable_for_new_repos(actor: @user)

        assert @push_protection.enabled_for_new_repos?
      end

      test "user disabled" do
        @push_protection.enable_for_new_repos(actor: @user)
        @push_protection.disable_for_new_repos(actor: @user)

        refute @push_protection.enabled_for_new_repos?
      end


      test "disabled if feature unavailable" do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        @push_protection.enable_for_new_repos(actor: @user)

        refute @push_protection.enabled_for_new_repos?
      end
    end

    context "custom messsage enabled" do
      test "user enabled" do
        @push_protection.enable_custom_message(actor: @user)
        assert @push_protection.custom_message_enabled?
      end

      test "user disabled" do
        @push_protection.enable_custom_message(actor: @user)
        @push_protection.disable_custom_message(actor: @user)
        refute @push_protection.custom_message_enabled?
      end

      test "disabled if Push Protection unavailable" do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        @push_protection.enable_custom_message(actor: @user)
        refute @push_protection.custom_message_enabled?
      end
    end

    context "custom message active" do
      test "true if feature enabled and message is set" do
        @push_protection.enable_custom_message(actor: @user)
        @business.set_push_protection_custom_message("custom msg", @user)
        assert @push_protection.custom_message_active?
      end

      test "false if feature disabled" do
        @push_protection.disable_custom_message(actor: @user)
        @business.set_push_protection_custom_message("custom msg", @user)
        refute @push_protection.custom_message_active?
      end

      test "false if message is empty" do
        @push_protection.enable_custom_message(actor: @user)
        @business.set_push_protection_custom_message("", @user)
        refute @push_protection.custom_message_active?
      end
    end
  end
end
