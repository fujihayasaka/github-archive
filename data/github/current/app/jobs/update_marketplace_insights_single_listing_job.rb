# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateMarketplaceInsightsSingleListingJob < ApplicationJob
  queue_as :site_stats

  RESTRAINT_LOCK_KEY = "update-marketplace-insights-lock"
  RESTRAINT_LOCK_CONCURRENT_JOBS = 2 # presto is limited in allowed concurrency
  RESTRAINT_LOCK_TTL = 10.minutes

  retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: 10

  around_perform do |_job, block|
    GitHub::Restraint.new.lock!(RESTRAINT_LOCK_KEY, RESTRAINT_LOCK_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      block.call
    end
  end

  def perform(listing:, date:, metric_types:, backfill_recurring: nil)
    listing = Marketplace::Listing.find_by(id: listing)
    return unless listing # listing may have been deleted

    GitHub.logger.info("update_marketplace_listing_single_insights", { "gh.marketplace.metric_types" => metric_types, "gh.marketplace.log_date" => date, "gh.marketplace.listing.name" => listing.name, "gh.marketplace.backfill_recurring" => backfill_recurring })

    with_write { listing.update_insights_for(date, metric_types) }

    if backfill_recurring.present?
      backfill_start, backfill_end = backfill_recurring

      if backfill_recurring.compact.size != 2 || backfill_start > backfill_end
        raise ArgumentError, "backfill_recurring should be an ordered array of two dates"
      end

      Range.new(backfill_start, backfill_end).each do |backfill_date|
        existing_insights = listing.insights.find_by(recorded_on: backfill_date)
        with_write do
          if metric_types.include?(:traffic)
            existing_insights&.update_metrics!(:traffic)
          else
            existing_insights&.update_metrics!(:transaction)
          end
        end
      end
    end
  end
end
