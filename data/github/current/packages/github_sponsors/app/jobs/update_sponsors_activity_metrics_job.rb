# typed: true
# frozen_string_literal: true

class UpdateSponsorsActivityMetricsJob < ApplicationJob
  queue_as :sponsors_activity

  retry_on_dirty_exit

  def perform
    SponsorsListing.with_approved_state.find_each do |listing|
      update_monthly_subscription_value(listing: listing) if listing.sponsorable.present?
    end
  end

  def update_monthly_subscription_value(listing:)
    with_write do
      metric = SponsorsActivityMetric.create_with(value: 0).create_or_find_by(
        sponsorable: listing.sponsorable,
        metric: :subscription_value,
        recorded_on: Date.today,
      )
      metric.update!(value: listing.subscription_value)
    end
  end
end
