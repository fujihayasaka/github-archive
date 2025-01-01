# typed: true
# frozen_string_literal: true

class SendSponsorshipEmailsJob < ApplicationJob
  queue_as :sponsors_emails

  DATADOG_PREFIX = "sponsors.sponsorship_emails"

  include GitHub::Memoizer

  def perform(sponsors_activity:)
    return unless GitHub.sponsors_enabled?

    return unless sponsors_activity.is_new_sponsorship?

    @sponsors_activity = sponsors_activity
    @tier = sponsors_activity.sponsors_tier
    @sponsor = sponsors_activity.sponsor
    @sponsorable = sponsors_activity.sponsorable
    @sponsorship = sponsors_activity.sponsorship

    return unless sponsorship.active?

    @listing = sponsorable.sponsors_listing
    @most_recent_prior_similar_activity = sponsors_activity.most_recent_prior_similar_activity

    # The payment could either be for the existing sponsorship or an additional
    # one-time payment.
    @sponsorship_amount = if sponsorship.concurrent_payment?(tier_paid: tier)
      tier.name
    else
      sponsorship.amount_per_cycle
    end

    with_write do
      send_new_sponsor_email
      send_now_sponsoring_email
      send_milestone_reached_email
    end
  end

  private

  attr_reader :tier, :sponsor, :sponsorable, :sponsorship, :sponsorship_amount, :sponsors_activity, :listing,
    :most_recent_prior_similar_activity

  sig { returns T.nilable(ActiveSupport::TimeWithZone) }
  def similar_email_most_recently_sent_at
    most_recent_prior_similar_activity&.timestamp
  end

  sig { returns T::Boolean }
  memoize def emailed_recently?
    approximate_email_timestamp = similar_email_most_recently_sent_at
    return false unless approximate_email_timestamp

    (Time.current - approximate_email_timestamp) <= SponsorsActivity::EMAIL_FREQUENCY_IN_MINUTES.minutes
  end

  def send_new_sponsor_email
    return if sponsorship_is_pending
    return unless sponsorship.send_new_sponsor_email?

    email_settings = listing.email_opt_outs
    return if email_settings.opted_out_of_all? || email_settings.opted_out_of_new_sponsorships?

    if emailed_recently?
      increment_skipping_duplicate_email("new_sponsor")
      return
    end

    if sponsorship.patreon?
      SponsorsPrimerMailer.patreon_new_sponsor(sponsor: sponsor, sponsorable: sponsorable).deliver_now
    else
      SponsorsPrimerMailer.new_sponsor(sponsorship, tier_paid: tier).deliver_now
    end

    sponsorship.new_sponsor_email_sent!
  end

  sig { params(email_type: String).void }
  def increment_skipping_duplicate_email(email_type)
    datadog_tags = [
      "sponsor_type:#{sponsor&.type}",
      "sponsorable_type:#{sponsorable&.type}",
      "patreon:#{sponsorship&.patreon?}",
      "action:#{sponsors_activity&.action}",
      "email:#{email_type}",
    ]
    GitHub.dogstats.increment("#{DATADOG_PREFIX}.skip_duplicate", tags: datadog_tags)
  end

  def send_now_sponsoring_email
    return if sponsorship_is_pending
    return if sponsors_activity.via_bulk_sponsorship?

    if emailed_recently?
      increment_skipping_duplicate_email("now_sponsoring")
      return
    end

    if sponsorship.patreon?
      SponsorsPrimerMailer.patreon_now_sponsoring(sponsorable: sponsorable, sponsor: sponsor).deliver_later
    else
      SponsorsPrimerMailer.now_sponsoring(
        sponsorable: sponsorable,
        sponsor: sponsor,
        sponsorship_amount: sponsorship_amount,
        tier: tier,
        sponsor_next_billing_date: sponsor.next_sponsors_billing_date,
        patreon: @sponsorship.patreon?,
      ).deliver_later
    end
  end

  def send_milestone_reached_email
    return if sponsorship_is_pending
    return if listing.milestone_email_sent?
    return unless listing.goals.none?

    email_settings = listing.email_opt_outs
    return if email_settings.opted_out_of_all? || email_settings.opted_out_of_milestone_reached?

    return unless milestone = SponsorsMilestone.for_listing(listing)

    if emailed_recently?
      increment_skipping_duplicate_email("milestone_reached")
      return
    end

    SponsorsPrimerMailer.milestone_reached(
      sponsorable: sponsorable,
      milestone_title: milestone.title,
    ).deliver_later

    listing.milestone_email_sent!
  end

  memoize def sponsorship_is_pending
    GitHub.flipper[:sponsors_pending_sponsorships].enabled?(sponsor) && sponsorship.pending?
  end
end
