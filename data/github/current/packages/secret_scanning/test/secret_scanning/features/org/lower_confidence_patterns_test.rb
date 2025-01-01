# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Org
  class OrgLowerConfidencePatternsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @business = create(:business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @org = create(:business_plus_org, business: @business)
      @user = create(:user)
      @token_scanning_org = SecretScanning::Features::Org::TokenScanning.new(@org)
      @lower_confidence_patterns_org = SecretScanning::Features::Org::LowerConfidencePatterns.new(@org)
      @lower_confidence_patterns_business = SecretScanning::Features::Business::LowerConfidencePatterns.new(@business)

      @org.stubs(:advanced_security_purchased?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Org::LowerConfidencePatterns.new(@org).nil?
      end
    end

    context "feature_available?" do
      test "returns false if the org does not have token scanning available" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @lower_confidence_patterns_org.feature_available?
      end

      test "returns false for free orgs without GHAS purchased" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
        free_org = create(:organization)
        free_org.stubs(:advanced_security_purchased?).returns(false)
        refute SecretScanning::Features::Org::LowerConfidencePatterns.new(free_org).feature_available?
      end

      test "returns true if org has purchased GHAS" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
        @org.stubs(:advanced_security_purchased?).returns(true)
        assert @lower_confidence_patterns_org.feature_available?
      end
    end

    context "dark_ship_enabled?" do
      test "returns false if the feature flag is disabled" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].disable
        refute @lower_confidence_patterns_org.dark_ship_enabled?
      end

      test "returns false if the org does not have token scanning available" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @lower_confidence_patterns_org.dark_ship_enabled?
      end

      test "returns true if the feature flag is enabled for the org" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@org)
        assert @lower_confidence_patterns_org.dark_ship_enabled?
      end

      test "returns true if the feature flag is enabled for the enterprise" do
        GitHub.flipper[FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP].enable(@business)
        assert @lower_confidence_patterns_org.dark_ship_enabled?
      end
    end

    context "enabled?" do
      test "returns false if not enabled by the org" do
        @org.config.disable(SecretScanning::Features::Org::LowerConfidencePatterns::CONFIG_KEY_USER_ENABLED, @user)
        refute @lower_confidence_patterns_org.enabled?
      end

      test "returns true if enabled by the org" do
        @org.config.enable(SecretScanning::Features::Org::LowerConfidencePatterns::CONFIG_KEY_USER_ENABLED, @user)
        assert @lower_confidence_patterns_org.enabled?
      end

      test "returns true if enabled by the enterprise" do
        @business.config.enable(SecretScanning::Features::Business::LowerConfidencePatterns::CONFIG_KEY_USER_ENABLED, @user)
        unless @lower_confidence_patterns_org.show_security_config_ux?
          assert @lower_confidence_patterns_org.enabled?
        end
      end
    end
  end
end
