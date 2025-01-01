# typed: true
# frozen_string_literal: true

class Hook::Event::MarketplacePurchaseEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets Marketplace::Listing
  auto_subscribed

  description "Marketplace listing is purchased, cancelled, or changed."

  event_attr :action, :subscription_item_id, :sender_id, required: true
  event_attr :pending_subscription_item_change_id, :previous_subscribable_id, :previous_quantity, :previous_plan_duration, :previously_on_free_trial, :previous_free_trial_ends_on

  # The Subscription Item the action affects
  def item
    @item ||= Billing::SubscriptionItem.find(subscription_item_id)
  end
  delegate :account, :subscribable, to: :item

  # The account that the listing is installed on. This will be be the user or standalone organization account
  # or the enterprise account organisation if the listing is installed on a self-serve enterprise account.
  memoize def installation_account
    item.organization_id ? Organization.find(item.organization_id) : account
  end

  # The previous Subscription Item
  def previous_listing_plan
    @previous_listing_plan ||=
      Marketplace::ListingPlan.find_by(id: previous_subscribable_id)
  end

  def pending_subscription_item_change
    @pending_subscription_item_change ||=
      Billing::PendingSubscriptionItemChange.find_by(id: pending_subscription_item_change_id)
  end

  # The user that triggered the event
  def sender
    @sender ||= User.find(sender_id)
  end
  alias :actor :sender

  # The marketplace listing this event is associated with
  def target_marketplace_listing
    item.listing
  end
end
