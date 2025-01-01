# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Business
  class BusinessGenericSecretsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @business = create(:business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @user = create(:user)
      @token_scanning_business = SecretScanning::Features::Business::TokenScanning.new(@business)
      @generic_secrets_business = SecretScanning::Features::Business::GenericSecrets.new(@business)

      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Business::GenericSecrets.new(@business).nil?
      end
    end

    context "feature_available?", skip_enterprise: true do
      test "returns false if GHAS not purchased" do
        @business.stubs(:advanced_security_purchased?).returns(false)
        refute @generic_secrets_business.feature_available?
      end

      test "returns false if the enterprise does not have token scanning available" do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @generic_secrets_business.feature_available?
      end

      test "returns false if feature flag is disabled, even if enabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].disable
        @business.config.enable(SecretScanning::Features::Business::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        refute @generic_secrets_business.feature_available?
      end

      test "returns false if business enablement feature flag is disabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_OWNER_ENABLEMENT].disable
        @business.config.enable(SecretScanning::Features::Business::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        refute @generic_secrets_business.feature_available?
      end

      test "returns true if feature flag is enabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_OWNER_ENABLEMENT].enable
        assert @generic_secrets_business.feature_available?
      end
    end

    context "enabled?", skip_enterprise: true do
      test "returns false if the feature flag is disabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].disable
        @business.config.enable(SecretScanning::Features::Business::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        refute @generic_secrets_business.enabled?
      end

      test "returns false if the business enablement feature flag is disabled" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_OWNER_ENABLEMENT].disable
        @business.config.enable(SecretScanning::Features::Business::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        refute @generic_secrets_business.enabled?
      end

      test "returns true if enabled by the enterprise" do
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_SCAN].enable
        GitHub.flipper[FeatureFlags::GENERIC_SECRETS_OWNER_ENABLEMENT].enable
        @business.config.enable(SecretScanning::Features::Business::GenericSecrets::CONFIG_KEY_USER_ENABLED, @user)
        assert @generic_secrets_business.enabled?
      end
    end
  end
end
