# typed: true
# frozen_string_literal: true

module Stafftools
  module Users
    class TrialLimitsComponent < ApplicationComponent
      def initialize(user:)
        @user = user
      end

      memoize def limiter
        EnterpriseTrialLimit.new(user: @user)
      end

      def current_limit
        limiter.created_trials_limit
      end

      def has_custom_limit?
        limiter.has_custom_limit?
      end

      def default_limit
        EnterpriseTrialLimit.default_limit
      end
    end
  end
end
