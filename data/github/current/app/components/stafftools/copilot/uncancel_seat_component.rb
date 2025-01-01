# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::UncancelSeatComponent < ApplicationComponent

  sig { returns(Copilot::Seat) }
  attr_reader :copilot_seat

  sig { returns(Date) }
  attr_reader :owner_cancellation_date

  sig { returns(T.nilable(T.any(::Organization, ::Business))) }
  attr_reader :owner

  sig { returns(T.nilable(User)) }
  attr_reader :user

  sig { returns(Copilot::SeatAssignment) }
  attr_reader :seat_assignment

  sig { returns(T::Boolean) }
  attr_reader :member

  sig { returns(T::Boolean) }
  attr_reader :suspended

  sig { params(copilot_seat: Copilot::Seat, seat_assignment: Copilot::SeatAssignment, owner_cancellation_date: Date, member: T::Boolean, suspended: T::Boolean).void }
  def initialize(copilot_seat, seat_assignment, owner_cancellation_date, member, suspended)
    @copilot_seat                   = copilot_seat
    @owner                          = T.let(seat_assignment.owner, T.nilable(T.any(::Organization, ::Business)))
    @user                           = T.let(copilot_seat.assigned_user, T.nilable(User))
    @seat_assignment                = seat_assignment
    @member                         = member
    @suspended                      = suspended
    @owner_cancellation_date        = owner_cancellation_date
  end

  # a seat can only be uncancelled if it has been cancelled (the seat assignment has a pending cancellation)
  sig { returns(T::Boolean) }
  def render?
    return false unless @seat_assignment.pending_cancellation?
    valid_user_assignment?
  end

  sig { returns(T::Boolean) }
  memoize def access_revoked?
    @seat_assignment.access_revoked?
  end

  sig { returns(T::Boolean) }
  def can_uncancel?
    return false if access_revoked?
    return false unless @seat_assignment.pending_cancellation?
    valid_user_assignment?
  end

  sig { returns(T::Boolean) }
  def valid_user_assignment?
    !!(@seat_assignment.assignable_type == "User" && @member && !@suspended && @user.present?)
  end
end
