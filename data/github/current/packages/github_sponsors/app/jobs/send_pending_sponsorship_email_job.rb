# typed: true
# frozen_string_literal: true

class SendPendingSponsorshipEmailJob < ApplicationJob
  queue_as :sponsors_emails

  retry_on_dirty_exit

  def perform(sponsorship)
    return unless GitHub.sponsors_enabled?
    return unless sponsorship.pending?
    return unless GitHub.flipper[:sponsors_pending_sponsorships].enabled?(sponsorship.sponsor)

    SponsorsPrimerMailer.pending_sponsorship(
      sponsorable: sponsorship.sponsorable,
      sponsor: sponsorship.sponsor,
      sponsorship_amount: sponsorship.amount_per_cycle
    ).deliver_later
  end
end
