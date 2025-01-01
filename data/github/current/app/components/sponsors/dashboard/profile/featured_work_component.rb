# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::FeaturedWorkComponent < ApplicationComponent
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  delegate :sponsorable_login, :sponsorable, to: :sponsors_listing

  def render?
    sponsors_listing.present?
  end

  memoize def featured_repositories
    sponsors_listing
      .featured_repos
      .preload(featureable: [:owner])
      .to_a
      .reject { |item| item.featureable&.owner.nil? }
      .map(&:featureable)
  end
end
