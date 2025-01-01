# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::ShortBioComponent < ApplicationComponent
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  def render?
    @sponsors_listing.present?
  end

  def short_description
    @sponsors_listing.featured_description
  end
end
