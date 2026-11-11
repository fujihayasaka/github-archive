# typed: strict
# frozen_string_literal: true

class SponsorsListingNoLongerSponsorableJob < ApplicationJob
  queue_as :billing

  retry_on_dirty_exit

  # Cancels all sponsorships for a Sponsors listing and notifies current sponsors
  #
  # sponsors_listing - the SponsorsListing whose active sponsorships will be cancelled
  # actor - the User responsible for the cancellation
  # reason - Symbol from Sponsorship::InstrumentationDependency::HYDRO_CANCELLATION_REASONS representing why
  #   the sponsorship is being cancelled
  sig { params(sponsors_listing: SponsorsListing, actor: T.nilable(User), reason: T.nilable(Symbol)).void }
  def perform(sponsors_listing:, actor:, reason: nil)
    @sponsors_listing = T.let(sponsors_listing, T.nilable(SponsorsListing))
    @actor = T.let(actor, T.nilable(User))
    @reason = T.let(reason, T.nilable(Symbol))

    return unless GitHub.sponsors_enabled?

    sponsors_listing.active_sponsorships.find_in_batches do |sponsorships|
      cancel(sponsorships)
      notify(sponsorships)
    end

    SyncSponsorsSearchIndicesJob.perform_later(sponsorable: sponsors_listing.sponsorable)
  end

  private

  sig { params(sponsorships: T::Array[Sponsorship]).void }
  def cancel(sponsorships)
    sponsorships.each do |sponsorship|
      Sponsorship.throttle_writes_with_retry do
        Billing::SubscriptionItem.throttle_writes_with_retry do
          sponsorship.cancel(actor: @actor, reason: @reason, force: true)
        end
      end
    end
  end

  sig { params(sponsorships: T::Array[Sponsorship]).void }
  def notify(sponsorships)
    sponsors_listing.email_sponsors_no_longer_sponsorable(sponsorships)
  end

  sig { returns(SponsorsListing) }
  def sponsors_listing
    T.must_because(@sponsors_listing) { "#perform takes a non-nil sponsors_listing" }
  end
end
