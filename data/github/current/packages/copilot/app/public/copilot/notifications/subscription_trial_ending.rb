# typed: strict
# frozen_string_literal: true

module Copilot
  module Notifications
    class SubscriptionTrialEnding < NotificationBase
      sig { override.returns(String) }
      def message
        days_left = copilot_user.days_left_on_trial
        "Your free trial of GitHub Copilot ends in #{days_left > 1 ? "#{numbers_to_words(days_left)} days" : "one day"}."
      end

      sig { override.returns(T::Boolean) }
      def send_condition
        super do
          days_left = copilot_user.days_left_on_trial

          return false unless days_left > 0

          days_left <= 3
        end
      end
    end
  end
end
