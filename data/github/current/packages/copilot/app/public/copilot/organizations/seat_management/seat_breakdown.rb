# typed: strict
# frozen_string_literal: true

# This class is used to populate the UI for seat management with current state of seats
# It will show the number of seats assigned, billed, and pending
#
# A SeatAssignment represents the user (or groups of users) the admin wishes to assign.
# A Seat represents a User from the SeatAssignment
#
# In Rails parlance, a SeatAssignment has_one "Assignable" (User/Invitation/Team/Entire Organization) and has_many Seats
#
# The Seats represent the billable entity which is derived from the SeatAssignment.
#
#In the string "A seats assigned (B billed / C pending)" we have:
#
# A = the Seats related to the SeatAssignments that are not being cancelled at the end of the billing month
# B = # of Seats for the Organization
# C = # of OrganizationInvitations
module Copilot
  module Organizations
    module SeatManagement
      class SeatBreakdown
        extend T::Helpers

        include ActionView::Helpers::TextHelper

        sig { returns(Integer) }
        attr_reader :seats_assigned

        sig { returns(Integer) }
        attr_reader :seats_billed

        sig { returns(Integer) }
        attr_reader :seats_pending

        sig { params(organization: ::Organization).void }
        def initialize(organization)
          seats_assigned = Copilot::Seat.connection.select_value(Arel.sql(<<-SQL, organization_id: organization.id))
            SELECT
            COUNT(*)
            FROM copilot_seats
            WHERE organization_id = :organization_id AND
            copilot_seat_assignment_id IN (
              SELECT
              id
              FROM copilot_seat_assignments
              WHERE organization_id = :organization_id
              AND pending_cancellation_date IS NULL
            )
            SQL

          seats_billed = Copilot::Seat.where(organization_id: organization.id).count
          seats_pending = Copilot::SeatAssignment.where(organization_id: organization.id, assignable_type: "OrganizationInvitation").count

          @seats_assigned = T.let(seats_assigned, Integer)
          @seats_billed   = T.let(seats_billed, Integer)
          @seats_pending  = T.let(seats_pending, Integer)
        end

        sig { returns({ seats_assigned: Integer, seats_billed: Integer, seats_pending: Integer, description: String }) }
        def to_object
          {
            seats_assigned: @seats_assigned,
            seats_billed: @seats_billed,
            seats_pending: @seats_pending,
            description: to_s,
          }
        end

        sig { returns(String) }
        def to_s
          io = StringIO.new
          io << "#{pluralize(@seats_assigned, "seat")} assigned"

          if @seats_billed + @seats_pending > 0
            io << " ("
            io << "#{@seats_billed} billed" if @seats_billed > 0
            io << " / " if @seats_billed > 0 && @seats_pending > 0
            io << "#{@seats_pending} pending" if @seats_pending > 0
            io << ")"
          end

          io.string
        end
      end
    end
  end
end
