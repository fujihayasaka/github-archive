# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Notifications
    class SubscriptionEnding < NotificationBase
      def message
        days_left = days_left_on_subscription(copilot_user)

        "Your access to GitHub Copilot ends in #{days_left > 1 ? "#{numbers_to_words(days_left)} days" : "one day"}."
      end

      # three days before subscription ends
      def send_condition
        super do
          days_left = days_left_on_subscription(copilot_user)
          return false unless days_left > 0

          days_left <= 3
        end
      end

      private

      def days_left_on_subscription(copilot_user)
        # they must have an active subscription item
        return -1 unless copilot_user.copilot_active_subscription_item.present?
        # it must be pending cancellation
        return -1 unless copilot_user.copilot_active_subscription_item.pending_cancellation?

        # return the number of days left on the subscription
        copilot_user.copilot_active_subscription_item.days_left_on_subscription
      end
    end
  end
end
