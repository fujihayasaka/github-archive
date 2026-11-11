# typed: true
# frozen_string_literal: true

class Sponsors::Payouts::MatchingFundStatusComponent < ApplicationComponent
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  def render?
    sponsors_listing.present?
  end

  def match_limit
    Billing::Money.new(SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS).format
  end

  def matched
    # If we've hit the match limit and overpaid them: just lie.
    return match_limit if sponsors_listing.reached_match_limit?

    Billing::Money.new(sponsors_listing.total_match_in_cents).format
  end

  def help_link
    "#{GitHub.help_url}/github/supporting-the-open-source-community-with-github-sponsors/" \
      "about-github-sponsors#about-the-github-sponsors-matching-fund"
  end
end
