# typed: true
# frozen_string_literal: true

class Stafftools::Copilot::SeatEmissionsComponent < ApplicationComponent
  attr_reader :seat_emissions

  def initialize(seat_emissions)
    @seat_emissions = seat_emissions
  end

  def render?
    @seat_emissions.present?
  end
end
