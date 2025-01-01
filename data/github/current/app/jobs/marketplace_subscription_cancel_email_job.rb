# typed: true
# frozen_string_literal: true

class MarketplaceSubscriptionCancelEmailJob < ApplicationJob

  queue_as :marketplace

  BATCH_SIZE = 25

  sig { returns(T::Boolean) }
  def self.enabled?
    GitHub.marketplace_enabled?
  end

  def perform(listing_id, cancelation_date)
    listing = Marketplace::Listing.find_by(id: listing_id)
    return unless listing

    with_write do
      listing.subscription_items.in_batches(of: BATCH_SIZE) do |batch_scope|
        Marketplace::Listing.throttle do
          batch_scope.each do |subscription_item|
            # subscription.account can either be a user or an organization
            MarketplaceMailer.send(:listing_subscriptions_cancelled, user: subscription_item.account, listing: listing, date: cancelation_date, plan_name: subscription_item.subscribable_name).deliver_now
          end
        end
      end
    end
  end
end
