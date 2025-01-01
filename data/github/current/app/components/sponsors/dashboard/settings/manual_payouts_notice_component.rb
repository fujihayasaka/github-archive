# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::ManualPayoutsNoticeComponent < ApplicationComponent
  def initialize(sponsorable:)
    @sponsorable = sponsorable
    @listing = @sponsorable&.sponsors_listing
  end

  private

  def render?
    @sponsorable.present? &&
      @listing &&
      !@listing.eligible_for_stripe_connect?
  end
end
