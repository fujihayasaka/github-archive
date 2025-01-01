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
      @repo.owner.stubs(:advanced_security_purchased?).returns(true)
    end

    context "initialize" do
      test "good input" do
        refute SecretScanning::Features::Repo::CustomPatterns.new(@repo).nil?
      end
    end

    context "feature_available?" do
      test "returns false if advanced security is not purchased" do
        @repo.owner.stubs(:advanced_security_purchased?).returns(false)
        refute @repo_custom_pattern.feature_available?
      end

      test "returns true if token scanning enabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        assert @repo_custom_pattern.feature_available?
      end

      test "false if token scanning disabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @repo_custom_pattern.feature_available?
      end
    end

    context "generate_expressions_with_ai_enabled?" do
      test "false on enterprise", enterprise_only: true do
        GitHub.flipper[FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI].enable(@repo)
        refute @repo_custom_pattern.generate_expressions_with_ai_enabled?
      end

      test "false on proxima if feature flag is disabled", skip_enterprise: true do
        GitHub.flipper[FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI].disable(@repo)
        emu_user = create :emu, :owner

        on_multi_tenant_enterprise(tenant: emu_user.enterprise_managed_business) do
          refute @repo_custom_pattern.generate_expressions_with_ai_enabled?
        end
      end

      test "true on proxima if feature flag is enabled", skip_enterprise: true do
        GitHub.flipper[FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI].enable(@repo)
        emu_user = create :emu, :owner

        on_multi_tenant_enterprise(tenant: emu_user.enterprise_managed_business) do
          assert @repo_custom_pattern.generate_expressions_with_ai_enabled?
        end
      end

      test "false if feature flag disabled", skip_enterprise: true, skip_in_multitenant_mode: true do
        GitHub.flipper[FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI].disable(@repo)
        refute @repo_custom_pattern.generate_expressions_with_ai_enabled?
      end

      test "true if feature flag enabled", skip_enterprise: true, skip_in_multitenant_mode: true do
        GitHub.flipper[FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI].enable(@repo)
        assert @repo_custom_pattern.generate_expressions_with_ai_enabled?
      end
    end
  end
end
