# typed: strict
# frozen_string_literal: true

module Codespaces
  module Access
    class SparkWorkbenchUsageChecker < Codespaces::Command

      sig { params(owner: T.untyped).void }
      def initialize(owner)
        @owner = owner
      end

      sig { override.params(prebuild: T::Boolean).returns(Codespaces::Access::AllowedResult) }
      def perform(prebuild: false)
        if @owner.feature_flag_enabled_or_raise?(:spark_unlimited_dev_compute) && user_has_prus_remaining? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          AllowedResult.new(AllowedResult::ALLOWED)
        elsif monthly_usage_seconds < allowed_usage_seconds
          AllowedResult.new(AllowedResult::ALLOWED)
        else
          AllowedResult.new(AllowedResult::DISALLOW_ENTITLEMENTS)
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def user_quotas
        {
          limits: {
            computeHours: (allowed_usage_seconds / 3600).round,
          },
          remaining: {
            computeHours: [(remaining_usage_seconds / 3600).round, 0].max,
            computeHoursPercentage: remaining_usage_percentage,
          }
        }
      end

      sig { returns(Integer) }
      memoize def allowed_usage_seconds
        if @owner.feature_flag_enabled_or_raise?(:spark_extended_dev_compute) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          Workbench::SparkCloudspaces::Dials::SparkWorkbenchExtendedUserUsageLimitSeconds.new(force_cache_miss: true).value
        elsif is_paid_user?
          Workbench::SparkCloudspaces::Dials::SparkWorkbenchPaidUserUsageLimitSeconds.new(force_cache_miss: true).value
        else
          Workbench::SparkCloudspaces::Dials::SparkWorkbenchFreeUserUsageLimitSeconds.new(force_cache_miss: true).value
        end
      end

      private

      sig { returns(Copilot::Public::User) }
      memoize def copilot_user
        Copilot::Public::User.new(@owner)
      end

      sig { returns(T::Boolean) }
      memoize def is_paid_user?
        !copilot_user.has_limited_access? || @owner.github_star? || @owner.microsoft_mvp?
      end

      sig { returns(T::Boolean) }
      memoize def user_has_prus_remaining?
        copilot_user.quota_percentage_remaining(feature: "premium_interactions") > 0
      end

      sig { returns(Integer) }
      def monthly_usage_seconds
        Codespaces::UsageRecord.
          for_spark_workbenches.current.
          where(owner: @owner).
          sum(&:usage_seconds) || 0
      end

      sig { returns(Integer) }
      def remaining_usage_seconds
        allowed_usage_seconds - monthly_usage_seconds
      end

      sig { returns(Integer) }
      def remaining_usage_percentage
        if @owner.feature_flag_enabled_or_raise?(:spark_unlimited_dev_compute) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          100
        else
          [(remaining_usage_seconds / allowed_usage_seconds.to_f * 100).round, 0].max
        end
      end
    end
  end
end
