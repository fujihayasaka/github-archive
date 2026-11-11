# typed: true
# frozen_string_literal: true

class Businesses::SeatLimits::ManageSeatLimitsComponent < ApplicationComponent

  sig { returns Business }
  attr_reader :business

  sig { params(business: Business).void }
  def initialize(business:)
    @business = business
  end
end
