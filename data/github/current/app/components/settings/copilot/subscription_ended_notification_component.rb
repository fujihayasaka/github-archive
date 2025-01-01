# typed: strict
# frozen_string_literal: true

module Settings
  module Copilot
    class SubscriptionEndedNotificationComponent < ApplicationComponent
      extend T::Sig

      sig { returns(T::Boolean) }
      attr_reader :has_subscription_ended

      sig { returns(T::Boolean) }
      attr_reader :subscription_ended_due_to_billing_trouble

      sig { returns(T::Boolean) }
      attr_reader :trial_only_subscription

      sig do
        params(
          has_subscription_ended: T::Boolean,
          subscription_ended_due_to_billing_trouble: T::Boolean,
          trial_only_subscription: T::Boolean,
        ).void
      end
      def initialize(has_subscription_ended, subscription_ended_due_to_billing_trouble, trial_only_subscription)
        @has_subscription_ended                    = has_subscription_ended
        @subscription_ended_due_to_billing_trouble = subscription_ended_due_to_billing_trouble
        @trial_only_subscription                   = trial_only_subscription
      end

      sig { returns(T::Boolean) }
      def render?
        has_subscription_ended
      end
    end
  end
end
