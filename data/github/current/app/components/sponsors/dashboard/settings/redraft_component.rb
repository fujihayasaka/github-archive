# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::RedraftComponent < ApplicationComponent
  def initialize(sponsorable:)
    @sponsorable = sponsorable
    @listing = sponsorable.sponsors_listing
  end

  private

  def render?
    @listing.approved?
  end
end
