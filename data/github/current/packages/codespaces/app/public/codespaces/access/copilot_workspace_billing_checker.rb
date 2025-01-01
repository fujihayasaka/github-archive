# typed: strict
# frozen_string_literal: true

module Codespaces
  module Access
    class CopilotWorkspaceBillingChecker < Codespaces::Command

      sig { params(owner: T.untyped).void }
      def initialize(owner)
        @owner = owner
      end

      sig { override.params(prebuild: T::Boolean).returns(Codespaces::Access::AllowedResult) }
      def perform(prebuild: false)
        return AllowedResult.new(AllowedResult::ALLOWED) if @owner.feature_flag_enabled_or_raise?(:codespaces_cwtp_no_limits) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        allowed_usage = Codespaces::Dials::CopilotWorkspaceUsageLimitSeconds.new(force_cache_miss: true).value
        monthly_usage = Codespaces::UsageRecord.
          for_copilot_workspaces.current.
          where(owner: @owner).
          sum(&:usage_seconds) || 0
        if monthly_usage < allowed_usage
          AllowedResult.new(AllowedResult::ALLOWED)
        else
          AllowedResult.new(AllowedResult::DISALLOW_ENTITLEMENTS)
        end
      end
    end
  end
end
