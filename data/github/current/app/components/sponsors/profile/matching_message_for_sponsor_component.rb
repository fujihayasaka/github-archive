# typed: true
# frozen_string_literal: true

class Sponsors::Profile::MatchingMessageForSponsorComponent < ApplicationComponent
  # sponsor - the User or Organization who is trying to make a sponsorship
  # listings - an Array of SponsorsListing records that the sponsor is trying to sponsor
  def initialize(sponsor:, listings: [])
    @sponsor = sponsor
    @listings = listings
  end

  private

  def render?
    return false if @sponsor.blank? || @listings.blank?
    return false if @sponsor.organization?

    matchable_listings.any?
  end

  memoize def matchable_listings
    GitHub::PrefillAssociations.prefill_associations(@listings, [:matches_ledger_entries])
    @listings.filter_map { |listing| listing if matchable_listing?(listing) }
  end

  def matchable_listing?(listing)
    listing.matchable? &&
      @sponsor.eligible_for_sponsorship_match?(sponsorable: listing.sponsorable)
  end

  def message
    noun = "sponsorship".pluralize(@listings.size)

    if matchable_listings.size < @listings.size
      "some of your #{noun}"
    else
      "your #{noun}"
    end
  end

  def help_url
    "#{GitHub.help_url}/articles/about-github-sponsors#about-the-github-sponsors-matching-fund"
  end
end
