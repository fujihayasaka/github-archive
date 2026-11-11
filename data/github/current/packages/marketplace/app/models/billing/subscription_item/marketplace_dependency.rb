# typed: true
# frozen_string_literal: true

module Billing::SubscriptionItem::MarketplaceDependency
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(Billing::SubscriptionItem))
    scope :with_marketplace_listing_plans_type, -> { where(subscribable_type: Marketplace::ListingPlan.name) }
    scope :with_any_active_marketplace_listing_plans, -> { with_marketplace_listing_plans_type.active }

    scope :joins_marketplace_listing_plans, -> {
      with_marketplace_listing_plans_type.
      joins("JOIN marketplace_listing_plans ON marketplace_listing_plans.id = subscription_items.subscribable_id").
      annotate("cross-schema-domain-query-exempted")
    }
    scope :joins_marketplace_listings, -> {
      joins_marketplace_listing_plans.
        joins("JOIN marketplace_listings on marketplace_listings.id = marketplace_listing_plans.marketplace_listing_id")
    }

    scope :for_marketplace_listing_plans, ->(listing_plans_ids) {
      with_marketplace_listing_plans_type.where(subscribable_id: listing_plans_ids)
    }

    scope :for_marketplace_listing, ->(marketplace_listing_or_id) do
      listing_plan_ids = Marketplace::ListingPlan.where(marketplace_listing_id: marketplace_listing_or_id).pluck(:id)
      for_marketplace_listing_plans(listing_plan_ids)
    end
  end

  class_methods do
    def for_users_on_marketplace_listing_plans(user_ids:, listing_plans_ids:)
      T.unsafe(self).where(subscribable_type: Marketplace::ListingPlan.name)
        .joins(:plan_subscription)
        .active
        .where(plan_subscriptions: { user_id: user_ids })
        .where(subscribable_id: listing_plans_ids)
    end
  end

  def record_marketplace_installation(installed_at: nil)
    T.unsafe(self).touch(:installed_at, time: installed_at)
  end

  def clear_marketplace_installation
    T.unsafe(self).update(installed_at: nil)
  end

  def async_all_marketplace_listing_plan_ids_for_listing
    return Promise.resolve([]) unless T.unsafe(self).subscribable_Marketplace_ListingPlan?
    T.unsafe(self).async_subscribable.then do |marketplace_listing_plan|
      Marketplace::ListingPlan.where(marketplace_listing_id: marketplace_listing_plan.marketplace_listing_id).pluck(:id)
    end
  end
end
