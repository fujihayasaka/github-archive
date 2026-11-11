# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class UserBillableRollbackFormComponent < ApplicationComponent
      # plan_subscription - a Billing::PlanSubscription
      # user - the User who owns the plan subscription
      def initialize(plan_subscription:, user:)
        @plan_subscription = plan_subscription
        @user = user
      end

      private

      attr_reader :plan_subscription, :user

      def render?
        plan_subscription.present? && GitHub.billing_enabled? && logged_in? && user.present? &&
          plan_subscription.user_id == user.id
      end

      def user_login
        user.login
      end

      memoize def purpose_summary
        plan_subscription.purpose_description
      end
    end
  end
end
