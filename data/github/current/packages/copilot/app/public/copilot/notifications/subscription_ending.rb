# typed: strict
# frozen_string_literal: true

module Copilot
  module Notifications
    class SubscriptionEnding < NotificationBase
      sig { override.returns(String) }
      def message
        days_left = days_left_on_subscription(copilot_user)

        "Your access to GitHub Copilot ends in #{days_left > 1 ? "#{numbers_to_words(days_left)} days" : "one day"}."
      end

      # three days before subscription ends
      sig { override.returns(T::Boolean) }
      def send_condition
        super do
          days_left = days_left_on_subscription(copilot_user)
          return false unless days_left > 0

          days_left <= 3
        end
      end

      private

      sig { params(copilot_user: Copilot::User).returns(Integer) }
      def days_left_on_subscription(copilot_user)
        # they must have an active subscription item
        return -1 unless (subscription = copilot_user.copilot_active_subscription_item).present?
        # it must be pending cancellation
        return -1 unless subscription.pending_cancellation?

        # return the number of days left on the subscription
        subscription.days_left_on_subscription
      end
    end
  end
end
