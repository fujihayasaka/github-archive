# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::CancelSeatComponent < ApplicationComponent

  sig { returns(Copilot::Seat) }
  attr_reader :copilot_seat

  sig { returns(Copilot::SeatAssignment) }
  attr_reader :seat_assignment

  sig { returns(Date) }
  attr_reader :owner_billing_cycle_end

  sig { returns(T.nilable(T.any(::Organization, ::Business))) }
  attr_reader :owner

  sig { returns(T.nilable(::User)) }
  attr_reader :user

  sig { returns(T::Boolean) }
  attr_reader :member

  sig { returns(T::Boolean) }
  attr_reader :suspended

  sig { params(copilot_seat: Copilot::Seat, seat_assignment: Copilot::SeatAssignment, owner_billing_cycle_end: Date, member: T::Boolean, suspended: T::Boolean).void }
  def initialize(copilot_seat, seat_assignment, owner_billing_cycle_end, member, suspended)
    @copilot_seat                   = copilot_seat
    @seat_assignment                = seat_assignment
    @owner                          = T.let(seat_assignment.owner, T.nilable(T.any(::Organization, ::Business)))
    @user                           = T.let(copilot_seat.assigned_user, T.nilable(::User))
    @owner_billing_cycle_end        = owner_billing_cycle_end
    @member                         = member
    @suspended                      = suspended
  end

  sig { returns(T::Boolean) }
  def render?
    !!(@seat_assignment.assignable_type == "User" || can_cancel_non_user?)
  end

  sig { returns(T::Boolean) }
  memoize def can_cancel_non_user?
    !!(@seat_assignment.assignable_type != "User" && (!@member || @suspended || !@user.present?))
  end
end
