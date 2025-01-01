# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::FeaturedWorkSearchModalComponent < ApplicationComponent
  def initialize(sponsors_listing:, query: "")
    @sponsors_listing = sponsors_listing
    @query = query
  end

  private

  attr_reader :sponsors_listing

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    sponsors_listing.present?
  end

  def featured_repos_limit
    ::SponsorsListingFeaturedItem::FEATURED_REPOS_LIMIT_PER_LISTING
  end

  memoize def featured_repos_remaining
    featured_repos_limit - sponsors_listing.featured_repos.count
  end
end
