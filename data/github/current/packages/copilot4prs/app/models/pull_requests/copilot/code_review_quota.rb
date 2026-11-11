# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    # Public: Checks if a given actor/user has availability quota to request a Copilot code review.
    class CodeReviewQuota
      include GitHub::ResilienceMixin

      sig { params(copilot_user: T.nilable(::Copilot::Public::User)).void }
      def initialize(copilot_user:)
        @copilot_user = copilot_user
      end

      # Public: Returns true if the user has remaining quota to request a Copilot code review.
      sig { returns(T::Boolean) }
      def has_quota_remaining?
        return false if faking_out_of_quota?
        remaining_quota > 0 || overages_enabled?
      end

      # Public: Returns the remaining quota for the user to request a Copilot code review.
      sig { returns(Float) }
      def remaining_quota
        return 0.0 if faking_out_of_quota?
        return 1.0 if Rails.env.development?
        with_database_error_fallback(fallback: 0.0) do
          copilot_user&.quota_percentage_remaining(feature: "premium_interactions") || 0.0
        end
      end

      # Public: Returns when the quota for the user will be reset.
      sig { returns(Date) }
      def quota_reset_date
        copilot_user&.quota_reset_date || DateTime.now.end_of_month
      end

      sig { returns(T::Boolean) }
      def overages_enabled?
        !!copilot_user&.overages_enabled?
      end

      private

      sig { returns(T.nilable(::Copilot::Public::User)) }
      def copilot_user
        @copilot_user
      end

      sig { returns(T::Boolean) }
      def faking_out_of_quota?
        !!copilot_user&.user&.feature_flag_enabled?(:copilot_code_review_out_of_quota, default: false)
      end
    end
  end
end
