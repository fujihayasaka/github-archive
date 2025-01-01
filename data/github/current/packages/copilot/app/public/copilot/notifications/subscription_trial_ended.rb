# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Notifications
    class SubscriptionTrialEnded < NotificationBase
      def message
        "Thank you for using GitHub Copilot. Your free trial has ended."
      end

      def send_condition
        super do
          return false unless copilot_user.copilot_active_subscription_item.present?
          return false unless copilot_user.copilot_active_subscription_item.free_trial_ends_on.present?

          Date.today >= copilot_user.copilot_active_subscription_item.free_trial_ends_on
        end
      end
    end
  end
end
