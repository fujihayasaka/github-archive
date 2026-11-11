# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::CancelSeatAssignmentComponent < ApplicationComponent
  sig { returns(Copilot::SeatAssignment) }
  attr_reader :copilot_seat_assignment

  sig { returns(Date) }
  attr_reader :owner_billing_cycle_end

  sig { returns(String) }
  attr_reader :schedule_form_url

  sig { returns(String) }
  attr_reader :cancel_form_url

  sig { params(copilot_seat_assignment: Copilot::SeatAssignment, owner_billing_cycle_end: Date, schedule_form_url: String, cancel_form_url: String).void }
  def initialize(copilot_seat_assignment, owner_billing_cycle_end, schedule_form_url:, cancel_form_url:)
    @copilot_seat_assignment        = copilot_seat_assignment
    @owner_billing_cycle_end        = owner_billing_cycle_end
    @schedule_form_url              = schedule_form_url
    @cancel_form_url                = cancel_form_url
  end

  sig { returns(T::Boolean) }
  def render?
    true
  end

  sig { returns(T::Boolean) }
  def user_assignment?
    copilot_seat_assignment.assignable_type == "User"
  end
end
