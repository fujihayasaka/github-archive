# typed: true
# frozen_string_literal: true

class SendSponsorshipCancellationEmailJob < ApplicationJob
  queue_as :sponsors_emails

  DATADOG_PREFIX = SendSponsorshipEmailsJob::DATADOG_PREFIX

  retry_on_dirty_exit

  sig { params(sponsors_activity: SponsorsActivity).void }
  def perform(sponsors_activity:)
    return unless GitHub.sponsors_enabled?
    return unless sponsors_activity.sponsors_listing

    sponsorable = sponsors_activity.sponsorable
    return unless sponsorable
    return if opted_out_of_cancelled_sponsorships?(sponsorable)

    if skip_sending_similar_email?(sponsors_activity)
      increment_skipping_duplicate_email(sponsors_activity)
      return
    end

    SponsorsPrimerMailer.sponsorship_cancellation_notice(
      sponsors_activity: sponsors_activity,
      sponsorable: sponsorable
    ).deliver_later
  end

  private

  sig { params(sponsors_activity: SponsorsActivity).returns(T::Boolean) }
  def skip_sending_similar_email?(sponsors_activity)
    most_recent_prior_similar_activity = sponsors_activity.most_recent_prior_similar_activity
    return false unless most_recent_prior_similar_activity

    approximate_email_timestamp = most_recent_prior_similar_activity.timestamp
    time_diff = Time.current - approximate_email_timestamp
    time_diff <= SponsorsActivity::EMAIL_FREQUENCY_IN_MINUTES.minutes
  end

  sig { params(sponsors_activity: SponsorsActivity).void }
  def increment_skipping_duplicate_email(sponsors_activity)
    datadog_tags = [
      "sponsor_type:#{sponsors_activity.sponsor.type}",
      "sponsorable_type:#{sponsors_activity.sponsorable&.type}",
      "patreon:#{sponsors_activity.patreon?}",
      "action:#{sponsors_activity.action}",
      "email:sponsorship_cancellation_notice",
    ]
    GitHub.dogstats.increment("#{DATADOG_PREFIX}.skip_duplicate", tags: datadog_tags)
  end

  sig { params(sponsorable: GitHubSponsors::Types::Sponsorable).returns(T::Boolean) }
  def opted_out_of_cancelled_sponsorships?(sponsorable)
    listing = T.must_because(sponsorable.sponsors_listing) { "#perform returns early when no listing" }
    email_settings = listing.email_opt_outs
    email_settings.opted_out_of_all? || email_settings.opted_out_of_cancelled_sponsorships?
  end
end
