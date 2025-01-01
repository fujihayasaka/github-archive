# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::StandaloneCancelSeatAssignmentComponent < ApplicationComponent
  extend T::Sig

  sig { returns(Copilot::SeatAssignment) }
  attr_reader :copilot_seat_assignment

  sig { returns(T.nilable(Business)) }
  attr_reader :business

  sig { returns(Date) }
  attr_reader :cancellation_date

  sig { params(copilot_seat_assignment: Copilot::SeatAssignment, cancellation_date: Date).void }
  def initialize(copilot_seat_assignment, cancellation_date)
    @copilot_seat_assignment = copilot_seat_assignment
    @business = T.let(copilot_seat_assignment.owner, T.nilable(Business))
    @cancellation_date = cancellation_date
  end

  sig { returns(T::Boolean) }
  def render?
    true
  end
end
