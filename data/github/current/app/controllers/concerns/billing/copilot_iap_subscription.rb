# typed: strict
# frozen_string_literal: true

module Billing::CopilotIapSubscription
  extend T::Helpers

  abstract!

  sig { params(user: User).returns(T::Boolean) }
  def copilot_iap_subscription?(user)
    return false if user.is_a?(Organization)

    item = Copilot::User.new(user).copilot_active_subscription_item
    return false unless item

    item.apple_in_app_purchase? || item.google_in_app_purchase?
  end

  # Generates a helpful message for the user about how to manage their subscription.
  sig { params(user: User).returns(String) }
  def simple_copilot_management_message(user)
    item = Copilot::User.new(user).copilot_active_subscription_item
    return "" unless item

    if item.apple_in_app_purchase?
      "Your Copilot subscription is billed through Apple App Store. You can manage your subscription through their platform."
    elsif item.google_in_app_purchase?
      "Your Copilot subscription is billed through Google Play. You can manage your subscription through their platform."
    else
      ""
    end
  end
end
