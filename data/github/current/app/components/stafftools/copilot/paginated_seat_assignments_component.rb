# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::PaginatedSeatAssignmentsComponent < ApplicationComponent

  sig { returns(ActiveRecord::Relation) }
  attr_reader :copilot_seat_assignments

  sig { params(copilot_seat_assignments: ActiveRecord::Relation).void }
  def initialize(copilot_seat_assignments)
    @copilot_seat_assignments        = copilot_seat_assignments
  end
end
