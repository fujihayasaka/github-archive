# typed: true
# frozen_string_literal: true

class Sponsors::Profile::FeaturedWorkComponent < ApplicationComponent
  include ResilienceHelper

  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  def render?
    sponsors_listing && featured_repositories.present?
  end

  memoize def featured_repositories
    with_database_error_fallback(fallback: []) do
      sponsors_listing.
        featured_repos.
        preload(featureable: [:owner, :primary_language]).
        to_a.
        reject { |item| item.featureable&.owner.nil? }
    end
  end
end
