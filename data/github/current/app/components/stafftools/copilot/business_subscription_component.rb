# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::BusinessSubscriptionComponent < ApplicationComponent

  sig { returns(T::Array[Copilot::Seat]) }
  attr_reader :seats

  sig { params(seats: T::Array[Copilot::Seat]).void }
  def initialize(seats)
    @seats         = seats
  end

  sig { returns(T::Boolean) }
  def render?
    @seats.any?
  end
end
