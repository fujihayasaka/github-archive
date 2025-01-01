# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class UpdateMarketplaceInsightsJob < ApplicationJob
  queue_as :site_stats

  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  # Queue an analytics update
  sig { params(date: T.nilable(T.any(Date, String)), metric_type: T.nilable(T::Array[Symbol])).void }
  def self.enqueue(date, metric_type)
    UpdateMarketplaceInsightsJob.perform_later(date, metric_type)
  end

  sig { params(date: T.nilable(T.any(Date, String)), metric_types: T.nilable(T::Array[Symbol])).void }
  def self.update_marketplace_listing_insights(date, metric_types)
    # If not performing for a specific date, go back to previous days to pick up
    # recurring transactions that have settled since the last run.
    backfill_recurring = date.nil?

    date ||= T.cast(Date.yesterday, Date)

    # Traffic metrics may not yet be available when this job runs, so will be updated
    # separately.
    metric_types ||= Marketplace::ListingInsight::ALL_METRIC_TYPES - [:traffic]


    GitHub.logger.info("update_marketplace_listing_insights", { "gh.marketplace.metric_types" => metric_types, "gh.marketplace.log_date" => date })


    if metric_types.include?(:traffic)
      if FeatureFlag.vexi.enabled?(:marketplace_batch_traffic_insights, default: false)
        UpdateMarketplaceTrafficInsightsJob.perform_later(date.to_date)
      else
        # will run traffic jobs serially as they are taking time and causing this error -Too many queued queries for "global.adhoc.adhoc_dotcom" , reverting this https://github.com/github/github/pull/152641
        Marketplace::Listing.publicly_listed.find_each do |listing|
          GitHub.logger.info("update_marketplace_listing_traffic_insights", { "gh.marketplace.metric_types" => metric_types, "gh.marketplace.log_date" => date, "gh.marketplace.listing.name" => listing.name })
          ActiveRecord::Base.connected_to(role: :writing) { listing.update_insights_for(date.to_date, metric_types) }
        end
      end
    else
      Marketplace::Listing.publicly_listed.find_each do |listing|
        GitHub.logger.info("update_marketplace_listing_before_job_insights", { "gh.marketplace.metric_types" => metric_types, "gh.marketplace.log_date" => date, "gh.marketplace.listing.name" => listing.name })
        UpdateMarketplaceInsightsSingleListingJob.perform_later(
          listing: listing.id,
          date: date,
          metric_types: metric_types,
          backfill_recurring: backfill_recurring ? [date - 3.days, date - 1.day] : nil
        )
      end
    end

    # I'm not sure if this metric makes sense anymore, but keeping it in for now
    insight_tags = metric_types.map { |type| "#{type}:true" }
    GitHub.dogstats.increment("marketplace.insights.updated", tags: insight_tags)
  end

  sig { params(date: T.nilable(T.any(Date, String)), metric_types: T.nilable(T.any(T::Array[Symbol], T::Array[String]))).void }
  def perform(date = nil, metric_types = nil)
    # Metric param may have been converted to a string in the queue
    metric_types = Array(metric_types).map(&:to_sym) unless metric_types.nil?

    self.class.update_marketplace_listing_insights(date, metric_types)
  end
end
