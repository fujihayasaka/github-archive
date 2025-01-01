# typed: true
# frozen_string_literal: true

module Stafftools
  module Users
    class TrialLimitsComponent < ApplicationComponent
      def initialize(user:)
        @user = user
      end

      memoize def enterprise_trial_limit
        EnterpriseTrialLimit.new(user: @user)
      end

      def current_limit
        enterprise_trial_limit.limit
      end

      def has_custom_limit?
        enterprise_trial_limit.has_custom_limit?
      end

      def default_limit
        EnterpriseTrialLimit.default_limit
      end
    end
  end
end
