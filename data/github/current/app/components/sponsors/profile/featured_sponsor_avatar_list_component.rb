# typed: true
# frozen_string_literal: true

class Sponsors::Profile::FeaturedSponsorAvatarListComponent < ApplicationComponent
  # sponsorable - a User or Organization that has a SponsorsListing
  # featured_sponsorships - An Array or ActiveRecord::Relation of SponsorsListingFeaturedItem records
  def initialize(sponsorable:, featured_sponsorships:)
    @sponsorable = sponsorable
    @featured_sponsorships = featured_sponsorships
  end

  private

  attr_reader :sponsorable, :featured_sponsorships

  def render?
    featured_sponsorships.any?
  end
end
