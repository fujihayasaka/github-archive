# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatAssignments
    class UserConverterCommand < Command
      extend T::Sig

      include SeatCreation

      # Sets up the command and makes sure it's for a User and has an Organization
      sig { params(seat_assignment: Copilot::SeatAssignment).void }
      def initialize(seat_assignment)
        valid_assignment = ensure_convertible!(seat_assignment, :USER)

        return if valid_assignment.nil?

        @seat_assignment = T.let(valid_assignment, Copilot::SeatAssignment)
        @owner = T.let(@seat_assignment.owner, ::Organization)
        @assigned_user = T.let(T.cast(@seat_assignment.assignable, ::User), ::User)
        @suspended = T.let(@assigned_user.suspended?, T::Boolean)
      end

      # User assignments are immediate - no cooling off period
      # this should be idempotent, so we can run it as many times as we want
      # 1. Check if the User SeatAssignment has already been converted by checking for a Seat pointing at this User and this SeatAssignment
      # 2. If it has not been converted, find ANY Seat for this User and Owner regardless of assignable type (like, there should only be one but just in case)
      # 3. If Seats are found, iterate through them
      # 4. If the SeatAssignment for the Seat is pending cancellation, update the Seat to point at this User and this SeatAssignment
      # 5. If the SeatAssignment has no other Seats associated, destroy it
      # 6. If the SeatAssignment is not pending cancellation and it's an Organization seat assignment, that's a problem. Raise an error
      sig { override.void }
      def perform
        seat_assignment_id = @seat_assignment.id

        GitHub.logger.with_named_tags(
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.org.id" => @owner.id, # User SeatAssignments currently are scoped to Organizations only.
          "gh.copilot.seat_assignment.id" => seat_assignment_id,
          "gh.copilot.assigned_user.id" => @assigned_user.id,
          "gh.user.suspended" => @suspended,
        ) do
          lock do
            # if an existing seat is related to this (org, user, seat assignment) tuple, return that as users can only have one seat per organization
            # and if they have an existing seat matching this User SeatAssignment, that means we've already converted this and cleaned up
            GitHub.logger.info("Checking for existing seat for this SeatAssignment")

            existing_seat = Copilot::Seat.find_by(
              seat_assignment: @seat_assignment,
              assigned_user: @assigned_user
            )

            if existing_seat.present?
              GitHub.logger.info("Found existing seat for this SeatAssignment, calling dedupe job")
              if @suspended
                # the user is suspended so they can't have a seat, let's clean up
                GitHub.logger.info("User is suspended, destroying existing seat")
                with_write do
                  existing_seat.destroy
                end
              end
              call_deduplication_job(@owner)
              return
            end

            # okay, it _seems_ that this seat assignment has not been converted yet
            # but there might be other Seats for this user and owner, so let's check that
            GitHub.logger.info("Checking for existing Seats for this User and Owner")
            other_assignment_seats = Copilot::Seat.for_assigned_user_and_owner(@assigned_user, @owner)

            if other_assignment_seats.any?
              GitHub.logger.info(
                "Found existing Seats for this User and Owner",
                "gh.copilot.other_assignment_seats.count" => other_assignment_seats.count,
              )

              # okay, we have other seats for this user and owner.  we need to do stuff based on their properties
              # so we'll call a method to do that
              other_assignment_seats.each do |seat|
                GitHub.logger.with_named_tags(
                  "gh.copilot.existing_seat.id" => seat.id,
                  "gh.copilot.existing_seat.seat_assignment.id" => seat.seat_assignment&.id,
                  "gh.copilot.existing_seat.seat_assignment.assignable_type" => seat.seat_assignment&.assignable_type,
                  "gh.copilot.existing_seat.seat_assignment.assignable_id" => seat.seat_assignment&.assignable_id,
                ) do
                  process_existing_seat(seat)
                end
              end

              call_deduplication_job(@owner)
            else
              if @suspended
                GitHub.logger.info("User is suspended, not creating new seat")
                return
              end

              GitHub.logger.info("Creating new Seat for this User and Owner")
              Copilot::Instrumenter.instrument_copilot_for_business_assignment_conversion(@seat_assignment, 0, 0, 1)

              insert_seats(
                [
                  {
                    assigned_user_id: T.must(@assigned_user.id),
                    copilot_seat_assignment_id: T.must(@seat_assignment.id),
                    organization_id: T.must(@owner.id),
                  }
                ],
                @seat_assignment,
              )
              call_deduplication_job(@owner)
            end
          end
        end
      end

      private

      # so, another seat exists for this user and owner (org)
      # that's okay sometimes.  sometimes it's not.
      # let's figure out what to do
      sig { params(seat: Copilot::Seat).void }
      def process_existing_seat(seat)
        GitHub.logger.info("Processing existing Seat")
        other_seat_assignment = T.must(seat.seat_assignment)
        assignable_type = other_seat_assignment.symbolized_assignable_type

        if @suspended
          # the user is suspended so they can't have a seat, let's clean up
          GitHub.logger.info("User is suspended, destroying existing seat")
          with_write do
            seat.destroy
          end
          return
        end

        if other_seat_assignment.pending_cancellation_date.present?
          with_write do
            # the other seat assignment (whether team or org) is pending cancellation
            # that means that we need to update this seat to point at the new User SeatAssignment because someone assigned this.
            GitHub.logger.info("Other SeatAssignment pending cancellation - updating existing Seat to point at this User SeatAssignment")
            seat.update!(seat_assignment: @seat_assignment)

            # if it has no other seats, we can destroy the other seat assignment
            GitHub.logger.info("Destroying other SeatAssignment if it has no other seats")
            other_seat_assignment.destroy! if other_seat_assignment.seats.count == 0
          end

          call_deduplication_job(@owner)
          return
        end

        # so the other seat assignment is active (not pending cancellation)
        # if this is an Organization SeatAssignment, we need to raise an error because we shouldn't be able to
        # both assign the entire organization AND individual assignables and we'll want to know about this
        if assignable_type == :ORGANIZATION
          msg = "User already has an #{assignable_type} Seat and cannot have User Seat"

          GitHub.logger.error(
            msg,
            "gh.copilot.assignable.type" => assignable_type,
          )
          error = Copilot::Errors::SeatAssignmentError.new(msg)
          Copilot::ErrorReporter.report!(
            error,
            copilot_seat_assignment: @seat_assignment,
            extra_details: {
              "gh.copilot.seat.id" => seat.id,
              "gh.copilot.seat_assignment.id" => other_seat_assignment.id,
            }
          )
          raise error
        end
      end

      sig { params(organization: ::Organization).void }
      def call_deduplication_job(organization)
        # TODO: add an enterprise deduplication job
        Copilot::SeatManagement::OrganizationDeduplicateJob.perform_later(T.must(organization.id))
      end

      sig do
        type_parameters(:A)
          .params(block: T.proc.returns(T.type_parameter(:A)))
          .returns(T.type_parameter(:A))
      end
      def lock(&block)
        lock_key = "user-converter-command-#{@owner.id}-#{@assigned_user.id}"

        restraint = GitHub::Restraint.new
        restraint.lock!(lock_key, 1, 5.minutes) do
          block.call
        end
      end
    end
  end
end
