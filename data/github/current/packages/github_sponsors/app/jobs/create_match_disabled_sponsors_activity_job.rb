# typed: true
# frozen_string_literal: true

class CreateMatchDisabledSponsorsActivityJob < ApplicationJob
  UNIQUENESS_TIME_WINDOW = 2.hours
  retry_on_dirty_exit
  queue_as :sponsors_application_processing

  attr_reader :listing

  def perform(listing:)
    return unless GitHub.sponsors_enabled?

    # set `@listing` so it can be used for `attr_reader` in other methods
    @listing = listing

    return if listing.blank? && !listing.approved?
    return if sponsorable.sponsorship_match_ineligible_from_age_or_spamminess?
    return if matchable_listings.blank?

    match_disabled_activity_attrs.each do |activity_attrs|
      existing_activity = SponsorsActivity.where("created_at >= ?", UNIQUENESS_TIME_WINDOW.ago)
        .find_by(activity_attrs)
      next if existing_activity

      SponsorsActivity.throttle_writes_with_retry { SponsorsActivity.create!(activity_attrs) }
    end
  end

  private

  def sponsorable
    @sponsorable ||= listing.sponsorable
  end

  def match_disabled_activity_attrs
    @match_disabled_activity_attrs ||= matchable_listings.map do |matchable_listing|
      match_disabled_activity_attrs_for(matchable_listing)
    end
  end

  def matchable_listings
    @matchable_listings ||= begin
      sponsorable_ids = sponsorable.active_sponsorships_as_sponsor_relation.pluck(:sponsorable_id)
      listings = SponsorsListing.
        includes(:sponsorable).
        where(sponsorable_id: sponsorable_ids)
      listings.select(&:matchable?)
    end
  end

  def match_disabled_activity_attrs_for(matched_listing)
    {
      timestamp: Time.at(listing.published_at),
      sponsorable_id: matched_listing.sponsorable_id,
      sponsor_id: sponsorable.id,
      sponsors_tier_id: matchable_tier_ids_by_listing_id[matched_listing.id],
      action: :sponsor_match_disabled,
    }
  end

  def matchable_tier_ids_by_listing_id
    @matchable_tier_ids_by_listing_id ||= begin
      tier_ids = sponsorable.sponsorships_as_sponsor.active.where(
        sponsorable_id: matchable_listings.pluck(:sponsorable_id),
      ).pluck(:subscribable_id)

      SponsorsTier.where(
        id: tier_ids,
      ).pluck(:sponsors_listing_id, :id).to_h
    end
  end
end
