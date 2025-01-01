# typed: true
# frozen_string_literal: true

class RelistNonSpammySponsorsListingJob < ApplicationJob
  queue_as :sponsors_application_processing
  retry_on_dirty_exit

  def perform(sponsorable:, actor: nil)
    return unless GitHub.sponsors_enabled?
    listing = sponsorable&.sponsors_listing
    return unless should_mark_not_spammy?(listing)

    listing.actor = actor
    SponsorsListing.throttle_writes_with_retry { listing.mark_not_spammy! }
  end

  def should_mark_not_spammy?(listing)
    return true if listing && listing.can_mark_not_spammy? && !listing.flagged_sponsorable?
    false
  end
end
