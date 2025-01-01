# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::FeaturedSponsorsComponent < ApplicationComponent
  include AvatarHelper

  sig { params(sponsors_listing: SponsorsListing).void }
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  sig { returns SponsorsListing }
  attr_reader :sponsors_listing

  sig { returns String }
  memoize def sponsorable_login
    @sponsors_listing.sponsorable_login
  end

  def render?
    @sponsors_listing
  end

  sig { returns T::Array[SponsorsListingFeaturedItem] }
  memoize def featured_sponsorships
    featured_sponsorships = @sponsors_listing.featured_sponsorships.preload(featureable: [sponsor: :profile]).to_a
    Sponsors::Profile::SponsorAvatarComponent.prefill_necessary_methods(
      featured_sponsorships.map(&:featureable),
      current_user: current_user
    )
    featured_sponsorships
  end

  sig { returns Integer }
  def total_featured_sponsorships
    featured_sponsorships.size
  end

  sig { returns Integer }
  def featured_sponsorships_limit
    SponsorsListingFeaturedItem::FEATURED_SPONSORSHIPS_LIMIT_PER_LISTING
  end

  sig { returns T::Boolean }
  def featured_sponsorships_enabled?
    @sponsors_listing.featured_sponsorships_settings.enabled?
  end

  sig { returns T::Boolean }
  def featured_sponsorships_automatic?
    @sponsors_listing.featured_sponsorships_settings.automatic?
  end
end
