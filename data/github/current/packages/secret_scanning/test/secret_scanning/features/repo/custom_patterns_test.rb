# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class RepoCustomPatternsTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper

    fixtures do
      @user = create(:user)
      @repo = create(:repository)
    end

    setup do
      @repo_custom_pattern = SecretScanning::Features::Repo::CustomPatterns.new(@repo)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Repo::CustomPatterns.new(@repo).nil?
      end
    end

    context "feature_available?" do
      test "returns false if secret scanning is not available" do
        SecretScanning::Features::AdvancedSecurityHelper.stubs(:secret_scanning_available?).returns(false)
        refute @repo_custom_pattern.feature_available?
      end

      test "returns true if token scanning enabled" do
        SecretScanning::Features::AdvancedSecurityHelper.stubs(:secret_scanning_available?).returns(true)
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        assert @repo_custom_pattern.feature_available?
      end

      test "false if token scanning disabled" do
        SecretScanning::Features::AdvancedSecurityHelper.stubs(:secret_scanning_available?).returns(true)
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @repo_custom_pattern.feature_available?
      end
    end

    context "generate_expressions_with_ai_enabled?" do
      test "false on enterprise", enterprise_only: true do
        enable_feature_flag(FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI, @repo)
        refute @repo_custom_pattern.generate_expressions_with_ai_enabled?
      end

      test "false on proxima if feature flag is disabled", skip_enterprise: true do
        disable_feature_flag(FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI, @repo)
        emu_user = create :emu, :owner

        on_multi_tenant_enterprise(tenant: emu_user.enterprise_managed_business) do
          refute @repo_custom_pattern.generate_expressions_with_ai_enabled?
        end
      end

      test "true on proxima if feature flag is enabled", skip_enterprise: true do
        enable_feature_flag(FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI, @repo)
        emu_user = create :emu, :owner

        on_multi_tenant_enterprise(tenant: emu_user.enterprise_managed_business) do
          assert @repo_custom_pattern.generate_expressions_with_ai_enabled?
        end
      end

      test "false if feature flag disabled", skip_enterprise: true, skip_in_multitenant_mode: true do
        disable_feature_flag(FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI, @repo)
        refute @repo_custom_pattern.generate_expressions_with_ai_enabled?
      end

      test "true if feature flag enabled", skip_enterprise: true, skip_in_multitenant_mode: true do
        enable_feature_flag(FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI, @repo)
        assert @repo_custom_pattern.generate_expressions_with_ai_enabled?
      end
    end
  end
end
