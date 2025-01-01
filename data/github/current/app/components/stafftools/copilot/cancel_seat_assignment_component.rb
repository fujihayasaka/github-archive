# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::CancelSeatAssignmentComponent < ApplicationComponent

  sig { returns(Copilot::SeatAssignment) }
  attr_reader :copilot_seat_assignment

  sig { returns(T.nilable(Organization)) }
  attr_reader :organization

  sig { params(copilot_seat_assignment: Copilot::SeatAssignment).void }
  def initialize(copilot_seat_assignment)
    @copilot_seat_assignment        = copilot_seat_assignment
    @organization                   = T.let(copilot_seat_assignment.organization, T.nilable(Organization))
  end

  sig { returns(T::Boolean) }
  def render?
    true
  end
end
