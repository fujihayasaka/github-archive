# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::DisableComponent < ApplicationComponent
  def initialize(sponsorable:)
    @sponsorable = sponsorable
    @sponsors_listing = sponsorable&.sponsors_listing
  end

  private

  attr_reader :sponsorable, :sponsors_listing

  def render?
    sponsors_listing&.can_disable?
  end

  def self_service_disable_allowed?
    sponsors_listing.allow_self_service_disable?
  end
end
