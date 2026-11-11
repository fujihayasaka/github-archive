# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::ReinstateSeatAssignmentComponent < ApplicationComponent
  sig { returns(Copilot::SeatAssignment) }
  attr_reader :copilot_seat_assignment

  sig { returns(String) }
  attr_reader :form_url

  sig { params(copilot_seat_assignment: Copilot::SeatAssignment, form_url: String).void }
  def initialize(copilot_seat_assignment, form_url:)
    @copilot_seat_assignment = copilot_seat_assignment
    @form_url = form_url
  end

  sig { returns(T::Boolean) }
  def render?
    copilot_seat_assignment.access_revoked?
  end
end
