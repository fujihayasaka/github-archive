# typed: true
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used for checking whether a Sponsorship is trusted.
#
# If both the sponsor and sponsorable are untrusted, we then look at the total dollar amount of
# sponsorships each has transacted with untrusted users. The check can therefore return `false`
# due to either the sponsor or sponsorable reaching that limit.
class Sponsors::TrustSystem::SponsorshipCheck
  UNTRUSTED_SPONSORSHIP_LIMIT_IN_DOLLARS = 100

  include Sponsors::TrustSystem::Enforcement
  include Sponsors::TrustSystem::Instrumentation

  def self.call(actor:, sponsor:, sponsorable:, tier:)
    self.new(
      actor: actor,
      sponsor: sponsor,
      sponsorable: sponsorable,
      tier: tier
    ).call
  end

  def initialize(actor:, sponsor:, sponsorable:, tier:)
    @actor = actor
    @sponsor = sponsor
    @sponsorable = sponsorable
    @tier = tier
  end

  def call
    meets_trust_threshold?
  end

  def meets_trust_threshold?
    return true unless @sponsor.untrusted_as_sponsor? && @sponsorable.untrusted_as_sponsorable?

    if exceeds_untrusted_sponsorable_limit?
      instrument_sponsorship_prohibited_due_to_sponsorable
      return !trust_enforced?(@sponsorable)
    end

    if exceeds_untrusted_sponsor_limit?
      instrument_sponsorship_prohibited_due_to_sponsor
      return !trust_enforced?(@sponsor)
    end

    true
  end

  private

  def listing
    return @_listing if defined?(@_listing)

    @_listing = @sponsorable.sponsors_listing
  end

  def listing_metadata
    return @_listing_metadata if defined?(@_listing_metadata)

    @_listing_metadata = listing.stafftools_metadata
  end

  def exceeds_untrusted_sponsorable_limit?
    @tier.monthly_price_in_dollars + untrusted_sponsorable_total > UNTRUSTED_SPONSORSHIP_LIMIT_IN_DOLLARS
  end

  def exceeds_untrusted_sponsor_limit?
    @tier.monthly_price_in_dollars + untrusted_sponsor_total > UNTRUSTED_SPONSORSHIP_LIMIT_IN_DOLLARS
  end

  def instrument_sponsorship_prohibited_due_to_sponsorable
    instrument_action_prohibited_for_sponsorable(:create_sponsorship,
      actor: @actor,
      sponsor: @sponsor,
      sponsorable: @sponsorable,
      listing: listing,
      listing_stafftools_metadata: listing_metadata,
      tier: @tier
    )
  end

  def instrument_sponsorship_prohibited_due_to_sponsor
    instrument_action_prohibited_for_sponsor(:create_sponsorship,
      actor: @actor,
      sponsor: @sponsor,
      sponsorable: @sponsorable,
      listing: listing,
      listing_stafftools_metadata: listing_metadata,
      tier: @tier
    )
  end

  def untrusted_sponsorable_total
    sponsorable_activities = @sponsorable.sponsors_activities.is_new_sponsorship.includes(:sponsor, :sponsors_tier)
    sponsorable_untrusted_sum_in_dollars = sponsorable_activities.sum do |activity|
      amount_in_dollars = activity.monthly_price_in_dollars
      activity.sponsor.untrusted_as_sponsor? ? amount_in_dollars : 0
    end
  end

  def untrusted_sponsor_total
    sponsor_activities = @sponsor.sponsors_activities_as_sponsor
      .is_new_sponsorship
      .includes(:sponsorable, :sponsors_tier)
    sponsor_untrusted_sum_in_dollars = sponsor_activities.sum do |activity|
      amount_in_dollars = activity.monthly_price_in_dollars
      activity.untrusted_sponsorable? ? amount_in_dollars : 0
    end
  end
end
