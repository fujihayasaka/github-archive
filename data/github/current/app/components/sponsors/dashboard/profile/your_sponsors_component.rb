# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::YourSponsorsComponent < ApplicationComponent
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  def render?
    sponsors_listing.present?
  end

  private

  attr_reader :sponsors_listing

  delegate :hide_past_sponsorships?, to: :sponsors_listing
end
