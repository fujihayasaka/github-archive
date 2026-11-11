# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::SortableFeaturedSponsorsComponent < ApplicationComponent
  sig { params(featured_sponsorships: T::Array[SponsorsListingFeaturedItem]).void }
  def initialize(featured_sponsorships:)
    @featured_sponsorships = featured_sponsorships
  end

  private

  sig { returns T::Array[SponsorsListingFeaturedItem] }
  attr_reader :featured_sponsorships
end
