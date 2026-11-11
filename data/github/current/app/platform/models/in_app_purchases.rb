# typed: strict
# frozen_string_literal: true

# This model understands how to determine which app store was used to purchase specific subscription items:
# Copilot for Individual and Individual Pro licenses. A more normalized, connection/array-based design was
# considered here but we are not expecting adding more products so flattening this out in this model is fine
# and will simplify the client-side code required to consume.
#
# Note: This does not represent if the user has access to these products via _any_ other mechanics other than
# in-app purchases. For example:
#   - A user could have access to Copilot via a Copilot for Business license provided by an organization they are
#     a member of but here the copilot method would return null.
#   - A user may have purchased a Copilot for Individual license via the web but here the copilot method would
#     return null.
# So just to reiterate: this is ONLY for in-app purchased subscriptions.
class Platform::Models::InAppPurchases

  sig { returns(::User) }
  attr_reader :user

  # We only allow users to purchase user-owned subscriptions.
  sig { params(user: ::User).void }
  def initialize(user)
    @user = user
  end

  # Returns the app store (or null for no in-app purchase) for where the Copilot for Individual license was
  # purchased.
  sig { returns(Promise[T.nilable(String)]) }
  def async_copilot
    Copilot::User.new(user).async_copilot_active_subscription_item.then do |subscription_item|
      next nil unless subscription_item

      Promise.all(
        [
          subscription_item.async_apple_in_app_purchase?,
          subscription_item.async_google_in_app_purchase?,
        ]
      ).then do |apple_in_app_purchase, google_in_app_purchase|
        if apple_in_app_purchase
          "apple"
        elsif google_in_app_purchase
          "google"
        else
          nil
        end
      end
    end
  end

  # Returns the app store (or null for no in-app purchase) for where the Individual Pro license was purchased.
  # Notice that we are not checking for the existence of a Google-purchased subscription for Pro since we currently
  # do not offer/support that.
  sig { returns(Promise[T.nilable(String)]) }
  def async_pro
    user.async_plan_subscription.then do |plan_subscription|
      plan_subscription&.apple_iap_subscription? ? "apple" : nil
    end
  end
end
