# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::UncancelSeatComponent < ApplicationComponent
  extend T::Sig

  sig { returns(Copilot::Seat) }
  attr_reader :copilot_seat

  sig { returns(Date) }
  attr_reader :organization_cancellation_date

  sig { returns(T.nilable(Organization)) }
  attr_reader :organization

  sig { returns(T.nilable(User)) }
  attr_reader :user

  sig { params(copilot_seat: Copilot::Seat, seat_assignment: Copilot::SeatAssignment, organization_cancellation_date: Date).void }
  def initialize(copilot_seat, seat_assignment, organization_cancellation_date)
    @copilot_seat                   = copilot_seat
    @organization                   = T.let(copilot_seat.organization, T.nilable(Organization))
    @user                           = T.let(copilot_seat.assigned_user, T.nilable(User))
    @seat_assignment                = seat_assignment
    @organization_cancellation_date = organization_cancellation_date
  end

  # a seat can only be uncancelled if it has been cancelled (the seat assignment has a pending cancellation)
  sig { returns(T::Boolean) }
  def render?
    @seat_assignment.pending_cancellation?
  end
end
