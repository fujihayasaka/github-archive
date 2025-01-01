# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    # Public: Checks if a given actor/user has availability quota to request a Copilot code review.
    class CodeReviewQuota

      sig { params(copilot_user: T.nilable(::Copilot::Public::User)).void }
      def initialize(copilot_user:)
        @copilot_user = copilot_user
      end

      # Public: Returns true if the user has remaining quota to request a Copilot code review.
      sig { returns(T::Boolean) }
      def has_quota_remaining?
        remaining_quota > 0
      end

      # Public: Returns the remaining quota for the user to request a Copilot code review.
      sig { returns(Float) }
      def remaining_quota
        rand(0.1..1.0) # TODO: Replace with actual implementation
      end

      private

      sig { returns(T.nilable(::Copilot::Public::User)) }
      def copilot_user
        @copilot_user
      end
    end
  end
end
