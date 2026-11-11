# typed: strict
# frozen_string_literal: true

class SponsorsProfileSetupReminderJob < ApplicationJob
  queue_as :mailers

  retry_on_dirty_exit

  sig { void }
  def perform
    # Sent 30 days after signup
    candidate_listings(30.days.ago).each do |listing|
      with_write do
        SponsorsPrimerMailer.first_profile_setup_reminder(sponsorable: listing.sponsorable).deliver_now
      end
    end

    # Sent one week before matching period starts,
    # about 7 weeks after signup
    candidate_listings(7.weeks.ago).each do |listing|
      with_write do
        SponsorsPrimerMailer.second_profile_setup_reminder(sponsorable: listing.sponsorable).deliver_now
      end
    end
  end

  private

  sig { params(period: ActiveSupport::TimeWithZone).returns(T::Array[SponsorsListing]) }
  def candidate_listings(period)
    from, to = T.unsafe(period).beginning_of_day, T.unsafe(period).end_of_day
    # Sponsors accepted in the waitlist
    SponsorsListing.accepted_in(from..to).with_draft_state.includes(:sponsorable).to_a
  end
end
