# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::StandalonePaginatedSeatAssignmentsComponent < ApplicationComponent

  sig { returns(WillPaginate::Collection) }
  attr_reader :copilot_seat_assignments

  sig { returns(Business) }
  attr_reader :business

  sig { params(copilot_seat_assignments: WillPaginate::Collection, business: Business).void }
  def initialize(copilot_seat_assignments, business)
    @copilot_seat_assignments = copilot_seat_assignments
    @business = business
  end
end
