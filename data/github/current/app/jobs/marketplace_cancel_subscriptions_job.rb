# typed: strict
# frozen_string_literal: true

class MarketplaceCancelSubscriptionsJob < ApplicationJob

  queue_as :marketplace

  BATCH_SIZE = 25

  sig { returns(T::Boolean) }
  def self.enabled?
    GitHub.marketplace_enabled?
  end

  sig { params(listing_id: Integer).void }
  def perform(listing_id)
    listing = Marketplace::Listing.find_by(id: listing_id)
    return unless listing

    with_write do
      listing.subscription_items.in_batches(of: BATCH_SIZE) do |batch_scope|
        Marketplace::Listing.throttle do
          batch_scope.each do |subscription_item|
            subscription_item.cancel!(force: true)
          end
        end
      end
    end
  end
end
