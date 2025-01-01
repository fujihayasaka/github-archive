# typed: true
# frozen_string_literal: true
class Businesses::SeatLimits::ListSeatLimitsComponent < ApplicationComponent
  extend T::Sig

  sig { returns Business }
  attr_reader :business

  sig { params(business: Business).void }
  def initialize(business:)
    @business = business
  end

  def render?
    GitHub.billing_enabled?
  end
end
