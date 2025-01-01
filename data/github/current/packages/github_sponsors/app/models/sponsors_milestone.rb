# typed: true
# frozen_string_literal: true

class SponsorsMilestone
  TOTAL_SPONSORS_COUNT_KIND = "total_sponsors_count"
  MONTHLY_SPONSORSHIP_AMOUNT_KIND = "monthly_sponsorship_amount"
  TOTAL_SPONSORS_COUNT_THRESHOLD = 10
  MONTHLY_SPONSORSHIP_AMOUNT_THRESHOLD = 25

  attr_reader :listing, :kind, :current_value

  def initialize(listing:, kind:, current_value:)
    @listing = listing
    @kind = kind
    @current_value = current_value
  end

  def self.for_listing(listing)
    sponsorable = listing.sponsorable
    sponsors_count = sponsorable
      .active_recurring_sponsorships_as_sponsorable
      .count
    monthly_sponsorship_amount = sponsorable.total_monthly_pledged_in_dollars.to_i

    if sponsors_count >= TOTAL_SPONSORS_COUNT_THRESHOLD
      new(listing: listing, kind: TOTAL_SPONSORS_COUNT_KIND, current_value: sponsors_count)
    elsif monthly_sponsorship_amount >= MONTHLY_SPONSORSHIP_AMOUNT_THRESHOLD
      new(listing: listing, kind: MONTHLY_SPONSORSHIP_AMOUNT_KIND, current_value: monthly_sponsorship_amount)
    end
  end

  delegate :sponsorable, to: :listing

  def title
    case kind
    when MONTHLY_SPONSORSHIP_AMOUNT_KIND
      "#{Billing::Money.new(current_value * 100).format(no_cents: true)} per month in sponsorships"
    when TOTAL_SPONSORS_COUNT_KIND
      "#{current_value} #{"sponsor".pluralize(current_value)}"
    end
  end
end
