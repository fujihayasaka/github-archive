# typed: strict
# frozen_string_literal: true

class ReviewPendingSponsorsListingsJob < ApplicationJob
  extend T::Sig

  queue_as :sponsors_application_processing
  retry_on_dirty_exit

  NUMBER_OF_LISTINGS_TO_REVIEW = 100

  sig { void }
  def perform
    return unless GitHub.sponsors_enabled?
    return unless feature_enabled?

    results = reviewable_listings.map do |listing|
      Sponsors::ReviewPendingSponsorsListing.call(sponsors_listing: listing)
    end

    if writing_enabled?
      results.each do |result|
        listing = result.sponsors_listing

        with_write do
          if result.approve?
            listing.approve!
          elsif listing.pending_approval?
            listing.require_additional_review!
          elsif listing.requires_additional_review?
            listing.stafftools_metadata&.touch(:reviewed_at)
          end
        end
      end
    end

    GitHub.dogstats.count("sponsors.review_pending_sponsors_listings_job.reviewed", results.count)
    GitHub.dogstats.count("sponsors.review_pending_sponsors_listings_job.approved", results.count(&:approve?))
  end

  private

  sig { returns T::Boolean }
  def feature_enabled?
    GitHub.flipper[:sponsors_automated_profile_reviews].enabled?
  end

  sig { returns T::Boolean }
  def writing_enabled?
    GitHub.flipper[:sponsors_automated_profile_reviews_write].enabled?
  end

  sig { returns T::Array[SponsorsListing] }
  def reviewable_listings
    candidate_listings = SponsorsListing
      .with_states(:pending_approval, :requires_additional_review)
      .where(parent_listing_id: nil) # do not review fiscally hosted profiles - those require specific validation
      .ordered_by_named_sort("approval_requested_at")
      .includes(:stafftools_metadata)

    pending_listings = candidate_listings
      .with_pending_approval_state
      .joins(:stafftools_metadata)
      .where("approval_requested_at < ?", 3.days.ago)

    requires_additional_review_listings = candidate_listings
      .with_requires_additional_review_state
      .joins(:stafftools_metadata)
      .where("reviewed_at IS NULL OR reviewed_at < ?", 3.weeks.ago)

    listings_to_review = pending_listings.or(requires_additional_review_listings)

    listings_to_review.take(NUMBER_OF_LISTINGS_TO_REVIEW)
  end
end
