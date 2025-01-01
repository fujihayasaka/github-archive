# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::CancelSeatComponent < ApplicationComponent

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

  sig { returns(T::Boolean) }
  def render?
    !@seat_assignment.pending_cancellation? && @organization.present?
  end

  sig { returns(T::Boolean) }
  def user_seat_through_org_or_team?
    type = @seat_assignment.assignable_type
    type == "Organization" || type == "Team"
  end
end
