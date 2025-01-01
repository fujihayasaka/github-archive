# typed: strict
# frozen_string_literal: true

class AutoApproveSponsorsListingJob < ApplicationJob
  extend T::Sig

  queue_as :sponsors_application_processing

  retry_on_dirty_exit

  locked_by timeout: 1.hour, key: ->(job) { job.arguments[0].id }

  class ListingAcceptanceError < StandardError; end

  sig { params(sponsors_listing: SponsorsListing).void }
  def perform(sponsors_listing)
    return unless GitHub.sponsors_enabled?

    @sponsors_listing = T.let(sponsors_listing, T.nilable(SponsorsListing))

    unless sponsors_listing.auto_approvable? && valid_listing_state?
      mark_as_auto_approval_failed_if_necessary
      return
    end

    Failbot.push(app: "github-sponsors")

    result = SponsorsListing.throttle_writes_with_retry do
      Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: sponsors_listing,
        actor: nil,
        automated: true,
      )
    end

    unless result.success?
      raise ListingAcceptanceError.new \
        "Failed to auto accept listing: #{result.errors.to_sentence}"
    end
  rescue StandardError
    mark_as_auto_approval_failed_if_necessary
    raise
  end

  private

  sig { returns SponsorsListing }
  def sponsors_listing
    T.must_because(@sponsors_listing) { "only called after #perform has initialized it to non-nil value" }
  end

  sig { void }
  def mark_as_auto_approval_failed_if_necessary
    if sponsors_listing.queued_for_auto_approval?
      SponsorsListing.throttle_writes_with_retry { sponsors_listing.auto_approval_failed! }
    end
  end

  sig { returns T::Boolean }
  def valid_listing_state?
    sponsors_listing.pending_approval? || sponsors_listing.queued_for_auto_approval?
  end
end
