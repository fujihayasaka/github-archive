# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Business
  class BusinessLowerConfidencePatternsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @business = create(:business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @user = create(:user)
      @token_scanning_business = SecretScanning::Features::Business::TokenScanning.new(@business)
      @lower_confidence_patterns_business = SecretScanning::Features::Business::LowerConfidencePatterns.new(@business)

      @business.stubs(:advanced_security_purchased?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Business::LowerConfidencePatterns.new(@business).nil?
      end
    end

    context "feature_available?" do
      test "returns false if the enterprise does not have token scanning available" do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @lower_confidence_patterns_business.feature_available?
      end

      test "returns false if the enterprise hasn't purchased GHAS" do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
        @business.stubs(:advanced_security_purchased?).returns(false)
        refute @lower_confidence_patterns_business.feature_available?
      end

      test "returns true if the enterprise has purchased GHAS" do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
        @business.stubs(:advanced_security_purchased?).returns(true)
        assert @lower_confidence_patterns_business.feature_available?
      end
    end

    context "dark_ship_enabled?" do
      test "returns false if the feature flag is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable
        refute @lower_confidence_patterns_business.dark_ship_enabled?
      end

      test "returns false if the enterprise has not purchased advanced security" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @lower_confidence_patterns_business.dark_ship_enabled?
      end

      test "returns true if the feature flag is enabled for the enterprise" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@business)
        assert @lower_confidence_patterns_business.dark_ship_enabled?
      end
    end

    context "enabled?" do
      test "returns true if enabled by the enterprise" do
        @business.config.enable(SecretScanning::Features::Business::LowerConfidencePatterns::CONFIG_KEY_USER_ENABLED, @user)
        assert @lower_confidence_patterns_business.enabled?
      end
    end
  end
end
