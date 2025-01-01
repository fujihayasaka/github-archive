# typed: strict
# frozen_string_literal: true

class AutoUpdateFeaturedSponsorsJob < ApplicationJob
  queue_as :sponsors_featured_sponsors_update

  retry_on_dirty_exit

  TOP_FEATURED_SPONSORSHIPS_COUNT = 10

  sig { params(listing: SponsorsListing).void }
  def perform(listing)
    return unless listing.featured_sponsorships_settings.enabled? &&
                listing.featured_sponsorships_settings.automatic?

    update_featured_sponsorships(listing)
  end

  private

  sig { params(listing: SponsorsListing).returns(T::Array[Integer]) }
  def fetch_current_featured_sponsors_ids(listing)
    listing.featured_sponsorships.pluck(:id)
  end

  sig { params(listing: SponsorsListing).void }
  def update_featured_sponsorships(listing)
    top_sponsorship_ids = fetch_top_sponsorship_ids(listing)
    current_featured_sponsors_ids = fetch_current_featured_sponsors_ids(listing)

    SponsorsListing.throttle_writes_with_retry do
      listing.with_lock do
        listing.set_featured_sponsorships(
          featured_sponsorships_params(
            current_featured_sponsors_ids: current_featured_sponsors_ids,
            top_sponsorship_ids: top_sponsorship_ids))
      end
    end
  end

  sig { params(listing: SponsorsListing).returns(T::Array[Integer]) }
  def fetch_top_sponsorship_ids(listing)
    top_sponsor_ids_by_lifetime_value = T.must(
      Sponsors::LifetimeSponsorshipValuesLoader.call(
        sponsorable_ids: [listing.sponsorable_id],
        viewer: T.must(listing.sponsorable)
      )
      .dig(listing.sponsorable_id))
      .sort_by { |_id, value| value }.reverse
      .map { |id, _value| id }
      .first(TOP_FEATURED_SPONSORSHIPS_COUNT)

    Sponsorship.where(sponsorable_id: listing.sponsorable_id)
      .in_order_of(:sponsor_id, top_sponsor_ids_by_lifetime_value)
      .pluck(:id)
  end

  sig do
    params(
      current_featured_sponsors_ids: T::Array[Integer],
      top_sponsorship_ids: T::Array[Integer])
      .returns(T::Array[T.untyped])
  end
  def featured_sponsorships_params(current_featured_sponsors_ids:, top_sponsorship_ids:)
    updated_featured_sponsors = current_featured_sponsors_ids.map { |id| { id: id, _destroy: true } }
    new_featured_sponsors = top_sponsorship_ids.map { |id| { featureable_id: id } }
    updated_featured_sponsors + new_featured_sponsors
  end
end
