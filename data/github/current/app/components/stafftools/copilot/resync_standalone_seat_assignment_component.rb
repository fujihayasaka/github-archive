# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::ResyncStandaloneSeatAssignmentComponent < ApplicationComponent
  sig { returns(Copilot::SeatAssignment) }
  attr_reader :copilot_seat_assignment

  sig { returns(T.nilable(Business)) }
  attr_reader :business

  sig { params(copilot_seat_assignment: Copilot::SeatAssignment).void }
  def initialize(copilot_seat_assignment)
    @copilot_seat_assignment = copilot_seat_assignment
    @business = T.let(copilot_seat_assignment.owner, T.nilable(Business))
  end

  sig { returns(T::Boolean) }
  def render?
    @copilot_seat_assignment.requires_conversion? && @copilot_seat_assignment.pending_cancellation_date.nil?
  end
end
