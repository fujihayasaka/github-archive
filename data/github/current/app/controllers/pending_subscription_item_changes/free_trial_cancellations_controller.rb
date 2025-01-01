# typed: strict
# frozen_string_literal: true

class PendingSubscriptionItemChanges::FreeTrialCancellationsController < ::PendingSubscriptionItemChangesController
  # Undo the free trial cancellation by
  # reverting the pending subscription item change to its existing subscription item quantity.

  sig { void }
  def update
    pending_subscription_item_change.undo_trial_cancellation

    if pending_subscription_item_change.errors.any?
      flash[:error] = pending_subscription_item_change.errors.full_messages.join(", ")
    else
      flash[:notice] = "Successfully resumed your free trial"
    end

    redirect_back(fallback_location: "/")
  end
end
