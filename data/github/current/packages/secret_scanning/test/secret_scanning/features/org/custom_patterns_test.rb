# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Org
  class OrgCustomPatternsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @user = create(:user)
      @org = create(:organization)
    end

    setup do
      @org_custom_pattern = SecretScanning::Features::Org::CustomPatterns.new(@org)
      @org.stubs(:advanced_security_purchased?).returns(true)
      SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Org::CustomPatterns.new(@org).nil?
      end
    end

    context "feature_available?" do
      test "returns false if advanced security is not purchased" do
        @org.stubs(:advanced_security_purchased?).returns(false)
        refute @org_custom_pattern.feature_available?
      end

      test "returns true if token scanning enabled" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
        assert @org_custom_pattern.feature_available?
      end

      test "false if token scanning disabled" do
        refute @org_custom_pattern.feature_available?
      end
    end

    context "generate_expressions_with_ai_enabled?" do
      test "false on enterprise", enterprise_only: true do
        GitHub.flipper[FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI].enable(@org)
        refute @org_custom_pattern.generate_expressions_with_ai_enabled?
      end

      test "false on proxima if feature flag is disabled", skip_enterprise: true do
        GitHub.flipper[FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI].disable(@org)
        emu_user = create :emu, :owner

        on_multi_tenant_enterprise(tenant: emu_user.enterprise_managed_business) do
          refute @org_custom_pattern.generate_expressions_with_ai_enabled?
        end
      end

      test "true on proxima if feature flag is enabled", skip_enterprise: true do
        GitHub.flipper[FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI].enable(@org)
        emu_user = create :emu, :owner

        on_multi_tenant_enterprise(tenant: emu_user.enterprise_managed_business) do
          assert @org_custom_pattern.generate_expressions_with_ai_enabled?
        end
      end

      test "false if feature flag disabled", skip_enterprise: true, skip_in_multitenant_mode: true do
        GitHub.flipper[FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI].disable(@org)
        refute @org_custom_pattern.generate_expressions_with_ai_enabled?
      end

      test "true if feature flag enabled", skip_enterprise: true, skip_in_multitenant_mode: true do
        GitHub.flipper[FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI].enable(@org)
        assert @org_custom_pattern.generate_expressions_with_ai_enabled?
      end
    end
  end
end
