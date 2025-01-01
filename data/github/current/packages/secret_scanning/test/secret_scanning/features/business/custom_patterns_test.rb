# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Business
  class BusinessCustomPatternsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @user = create(:user)
      @business = create(:business)
    end

    setup do
      @custom_patterns = SecretScanning::Features::Business::CustomPatterns.new(@business)
      @business.stubs(:advanced_security_purchased?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Business::CustomPatterns.new(@business).nil?
      end
    end

    context "feature_available?" do
      test "returns false if GHAS not purchased" do
        @business.stubs(:advanced_security_purchased?).returns(false)
        refute @custom_patterns.feature_available?
      end

      test "returns true if token scanning enabled" do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
        assert @custom_patterns.feature_available?
      end

      test "false if token scanning disabled" do
        SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
        refute @custom_patterns.feature_available?
      end
    end

    context "generate_expressions_with_ai_enabled?" do
      test "false on enterprise", enterprise_only: true do
        enable_feature_flag(FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI, @business)
        refute @custom_patterns.generate_expressions_with_ai_enabled?
      end

      test "false on proxima if feature flag disabled", skip_enterprise: true do
        disable_feature_flag(FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI, @business)

        on_multi_tenant_enterprise(tenant: @business) do
          refute @custom_patterns.generate_expressions_with_ai_enabled?
        end
      end

      test "true on proxima if feature flag enabled", skip_enterprise: true do
        enable_feature_flag(FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI, @business)

        on_multi_tenant_enterprise(tenant: @business) do
          assert @custom_patterns.generate_expressions_with_ai_enabled?
        end
      end

      test "false if feature flag disabled", skip_enterprise: true, skip_in_multitenant_mode: true do
        disable_feature_flag(FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI, @business)
        refute @custom_patterns.generate_expressions_with_ai_enabled?
      end

      test "true if feature flag enabled", skip_enterprise: true, skip_in_multitenant_mode: true do
        enable_feature_flag(FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI, @business)
        assert @custom_patterns.generate_expressions_with_ai_enabled?
      end
    end
  end
end
