# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::UncancelSeatAssignmentComponent < ApplicationComponent

  sig { returns(Copilot::SeatAssignment) }
  attr_reader :copilot_seat_assignment

  sig { returns(T.nilable(Organization)) }
  attr_reader :organization

  sig { params(copilot_seat_assignment: Copilot::SeatAssignment, form_url: String).void }
  def initialize(copilot_seat_assignment, form_url:)
    @copilot_seat_assignment = copilot_seat_assignment
    @organization = T.let(copilot_seat_assignment.organization, T.nilable(Organization))
    @form_url = form_url
  end

  sig { returns(T::Boolean) }
  def render?
    copilot_seat_assignment.pending_cancellation_date?
  end
end
