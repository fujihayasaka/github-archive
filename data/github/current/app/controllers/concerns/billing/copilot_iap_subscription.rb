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
end
