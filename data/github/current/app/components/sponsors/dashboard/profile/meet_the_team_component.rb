# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::MeetTheTeamComponent < ApplicationComponent
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
    sponsors_listing.sponsorable_login
  end

  sig { returns T::Boolean }
  def render?
    sponsors_listing.for_organization?
  end

  sig { returns T::Array[SponsorsListingFeaturedItem] }
  memoize def featured_users
    sponsors_listing.featured_users.preload(featureable: :profile).to_a
  end

  sig { returns Integer }
  def total_featured_users
    featured_users.size
  end

  sig { returns Integer }
  def featured_users_limit
    SponsorsListingFeaturedItem::FEATURED_USERS_LIMIT_PER_LISTING
  end

  memoize def react_list_props
    {
      featuredItems: featured_users.map do |item|
        {
          id: item.id,
          featureableId: item.featureable.id,
          profileName: item.featureable.profile_name,
          description: item.description,
          title: item.featureable.display_login,
          avatarUrl: avatar_url_for(item.featureable, 50),
        }
      end
    }
  end
end
