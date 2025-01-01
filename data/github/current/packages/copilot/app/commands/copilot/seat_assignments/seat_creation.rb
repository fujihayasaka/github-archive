# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatAssignments
    module SeatCreation
      extend T::Helpers

      include Signatures

      MAX_THROTTLE_RETRIES = 4

      abstract!

      # This method will check the seat assignment to see that it is setup correctly to convert
      # NOTE: This will raise an error if the seat assignment is not convertible and it will destroy the seat assignment and associated
      #       seats if the seat assignment is pending cancellation before today
      sig { params(seat_assignment: Copilot::SeatAssignment, converter_type: Symbol).returns(T.nilable(Copilot::SeatAssignment)) }
      def ensure_convertible!(seat_assignment, converter_type)
        GitHub.logger.with_named_tags(
          "code.function" => "ensure_convertible!",
          "code.namespace" => "Copilot::SeatAssignments::SeatCreation",
          "gh.copilot.seat_assignment.id" => seat_assignment.id,
          "gh.copilot.converter_type" => converter_type,
        ) do
          seat_assignment.make_sure_owner_is_populated!

          # check assignable type matches the passed in type
          Kernel.raise(
            Copilot::Errors::SeatAssignmentError,
            "Expected assignable to be of type #{converter_type}, but got #{seat_assignment.assignable_type}",
          ) unless seat_assignment.symbolized_assignable_type == converter_type

          # check owner type
          owner = case converter_type
          when :ENTERPRISE_TEAM
            # EnterpriseTeams MUST be owned by a Business
            Kernel.raise Copilot::Errors::SeatAssignmentInvalidOwnerTypeError, "Owner must be business" unless seat_assignment.owner_type == "Business"
            T.cast(seat_assignment.owner, ::Business)
          else
            Kernel.raise Copilot::Errors::SeatAssignmentInvalidOwnerTypeError, "Owner must be organization" unless seat_assignment.owner_type == "Organization"
            T.cast(seat_assignment.owner, ::Organization)
          end

          # check assignable owner
          case converter_type
          when :ENTERPRISE_TEAM
            assigned_team = T.cast(seat_assignment.assignable, ::EnterpriseTeam)
            Kernel.raise Copilot::Errors::SeatAssignmentAssignableError, "A business cannot assign an EnterpriseTeam from another business" unless assigned_team.business == owner
          when :ORGANIZATION
            assigned_organization = T.cast(seat_assignment.assignable, ::Organization)
            Kernel.raise Copilot::Errors::SeatAssignmentAssignableError, "An organization cannot assign another organization" unless assigned_organization == owner
          when :TEAM
            assigned_team = T.cast(seat_assignment.assignable, ::Team)
            Kernel.raise Copilot::Errors::SeatAssignmentAssignableError, "An organization cannot assign a Team from another organization" unless assigned_team.organization == owner
          when :USER
            assigned_user = T.cast(seat_assignment.assignable, ::User)
            Kernel.raise Copilot::Errors::SeatAssignmentAssignableError, "An organization cannot assign a User from another organization" unless owner.member_ids.include?(assigned_user.id)
          end

          # check if seat assignment is pending cancellation
          if seat_assignment.pending_cancellation_date.present?
            if seat_assignment.pending_cancellation_date < Date.today
              with_write do
                GitHub.logger.info("SeatAssignment is pending cancellation and the date is in the past - destroying any seats")
                Copilot::Seat.where(seat_assignment: seat_assignment).destroy_all
                GitHub.logger.info("SeatAssignment is pending cancellation and the date is in the past - destroying the SeatAssignment")
                seat_assignment.destroy
              end
              GitHub.dogstats.increment("copilot.seat_assignment_conversion.skipped", tags: ["type:#{converter_type.to_s.downcase}", "reason:destroyed_due_to_cancellation"])
              Kernel.raise Copilot::Errors::SeatAssignmentPendingCancellationError, "SeatAssignment had pending cancellation date in the past and was destroyed"
            else
              GitHub.logger.info(
                "Skipping conversion of SeatAssignment because it is pending cancellation",
                "gh.copilot.seat_assignment.pending_cancellation_date" => seat_assignment.pending_cancellation_date,
              )
              GitHub.dogstats.increment("copilot.seat_assignment_conversion.skipped", tags: ["type:#{converter_type.to_s.downcase}", "reason:pending_cancellation"])
            end
          end

          seat_assignment
        end
      end

      # Creates Copilot::Seat records with the given attributes.
      sig do
        params(
          seats: T::Array[
            {
              assigned_user_id: Integer,
              copilot_seat_assignment_id: Integer,
              organization_id: T.nilable(Integer), # TODO: Deprecate this column (Enterprise Teams don't have this)
            }
          ],
          seat_assignment: Copilot::SeatAssignment,
          actor: T.nilable(::User), # pass in a user if you want to override the SeatAssignment assigning_user
        ).void
      end
      def insert_seats(seats, seat_assignment, actor: nil)
        GitHub.logger.with_named_tags({
          "code.function": "insert_seats",
          "code.namespace": "Copilot::SeatAssignments::SeatCreation",
          "gh.copilot.seat_creation.seats.count": seats.count,
          "gh.copilot.seat_creation.actor": actor&.display_login,
        }) do
          with_read do
            if seats.empty?
              # this seems like a bad-ish thing
              # like, why are we trying to insert 0 seats?
              # i think it's probably Casey's fault
              GitHub.dogstats.increment("copilot.seat_creation.no_seats")

              message = "No seats to insert"
              GitHub.logger.error(message)

              # we're gonna tell a grownup about this and then we're gonna leave
              Copilot::ErrorReporter.report!(
                Copilot::Errors::SeatCreationError.new(message),
                extra_details: {
                  "gh.copilot.seats" => seats,
                  "gh.actor.id" => actor&.id,
                }
              )
              return
            end

            seat_assignment_id = seat_assignment.id

            actor = audit_log_actor(seat_assignment, actor)

            if seat_assignment.owner_type == "Organization"
              owner = T.cast(seat_assignment.owner, ::Organization)
              organization_id = owner.id
            else
              organization_id = nil
              owner = T.cast(seat_assignment.owner, ::Business)
            end

            GitHub.logger.with_named_tags({
              "gh.copilot.seat_assignment.id": seat_assignment_id,
              "gh.copilot.seat_assignment.owner.id": owner.id,
              "gh.copilot.seat_assignment.owner.type": owner.class.name.to_s,
            }) do
              business_trial = organization_id.present? ? Copilot::BusinessTrial.for_organization_id(organization_id) : nil

              if business_trial.present? && business_trial.startable?
                GitHub.logger.info(
                  "Starting business trial",
                  "gh.copilot.business_trial.id": business_trial.id,
                )
                with_write do
                  business_trial.start_trial!
                end
              end

              # we are going to lock here so that this is run only once concurrently for a given seat_assignment_id
              lock_seat_creation("copilot.seat_creation.#{seat_assignment_id}") do
                GitHub.logger.info("Inserting seats")

                write_seats(seats, actor, owner)

                GitHub.logger.info("Inserted seats")
              end
            end
          end
        end
      rescue GitHub::Restraint::UnableToLock => e
        GitHub.logger.error("Unable to lock for seat creation", "error": e.message)
        # this probably isn't a HUGE deal, but we should know about it
        Copilot::ErrorReporter.report!(
          Copilot::Errors::SeatCreationLockError.from_error(e),
          extra_details: {
            "gh.copilot.seats" => seats,
            "gh.actor.id" => actor&.id,
          }
        )
      end

      # Writes the given seats to the database.
      sig do
        params(
          seats: T::Array[
            {
              assigned_user_id: Integer,
              copilot_seat_assignment_id: Integer,
              organization_id: T.nilable(Integer), # Enterprise Teams don't have this and we will drop this column in the future
            }
          ],
          actor: T.nilable(::User),
          owner: T.any(::Business, ::Organization),
          notify_user: T::Boolean,
        ).void
      end
      def write_seats(seats, actor, owner, notify_user = true)
        with_write do
          standalone = owner.present? && owner.is_a?(::Business)
          seats.in_groups_of(500, false) do |batch_scope|
            Copilot::Seat.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              # FYI THIS DOES NOT CREATE A SEAT HISTORY RECORD
              Copilot::Seat.insert_all(batch_scope)
            end
            GitHub.logger.info("Inserted batch of seats", "gh.copilot.seat_creation.batch_size": batch_scope.size)

            batch_scope.each do |seat|
              Copilot::Instrumenter.instrument_copilot_for_business_seat_added(
                owner,
                seat[:assigned_user_id],
                actor,
                :batch_insert,
              ) if notify_user

              if standalone
                # THIS JOB CREATES A SEAT HISTORY RECORD
                Copilot::SeatManagement::EnterpriseSeatAssignedJob.perform_later(
                  T.cast(owner.id, Integer),
                  seat[:assigned_user_id],
                  notify_user: notify_user,
                )
              else
                # THIS JOB CREATES A SEAT HISTORY RECORD
                Copilot::SeatManagement::SeatAssignedJob.perform_later(
                  seat[:organization_id],
                  seat[:assigned_user_id],
                )
              end
            end

            GitHub.dogstats.increment("copilot.seat_creation.seats_inserted", by: batch_scope.size)
          end
        end
      rescue Freno::Throttler::Error => e
        # so, we got in trouble. we were moving too fast for too long and now we're grounded
        # we gotta tell someone cause this could mean that the seat assignment conversion didn't finish
        GitHub.logger.error("Throttled trying to insert seats and exhausted retries", "error": e.message)
        Copilot::ErrorReporter.report!(
          Copilot::Errors::SeatCreationThrottleError.from_error(e),
          extra_details: {
            "gh.copilot.seat_assignment.id" => T.must(seats.first).dig(:copilot_seat_assignment_id),
            "gh.actor.id" => actor&.id,
            "gh.copilot.seat_assignment.owner.id" => owner.id,
          }
        )
        Kernel.raise e, "Exhausted retries for seat creation"
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        # this is a big deal, we should know about it
        GitHub.logger.error("Failed to insert seats", "error": e.message)

        Copilot::ErrorReporter.report!(
          Copilot::Errors::SeatCreationError.from_error(e),
          extra_details: {
            "gh.copilot.seat_assignment.id" => T.must(seats.first).dig(:copilot_seat_assignment_id),
            "gh.actor.id" => actor&.id,
            "gh.copilot.seat_assignment.owner.id" => owner.id,
          }
        )
        Kernel.raise e
      end

      sig do
        type_parameters(:A)
          .params(lock_key: String, block: T.proc.returns(T.type_parameter(:A)))
          .returns(T.type_parameter(:A))
      end
      def lock_seat_creation(lock_key, &block)
        restraint = GitHub::Restraint.new
        restraint.lock!(lock_key, 1, 5.minutes) do
          GitHub.logger.info("Lock acquired for seat creation", "gh.copilot.lock_key": lock_key)

          block.call

          GitHub.logger.info("Lock released for seat creation", "gh.copilot.lock_key": lock_key)
        end
      end

      private

      sig { params(seat_assignment: Copilot::SeatAssignment, actor: T.nilable(::User)).returns(T.nilable(::User)) }
      def audit_log_actor(seat_assignment, actor)
        # seat_assignment.assigning_user can be null if assigning_user no longer exists by the time insert_seats is called
        if actor.nil? && seat_assignment.assigning_user.nil?
          GitHub.logger.info(
            "Actor is nil and seat assignment's assigning user no longer exists",
            "code.function": "insert_seats",
            "code.namespace": "Copilot::SeatAssignments::SeatCreation",
            "gh.copilot.seat_assignment.id": seat_assignment.id,
            "gh.copilot.seat_assignment.assigning_user_id": seat_assignment.assigning_user_id,
          )
          return nil
        end

        actor = if !seat_assignment.assigning_user.nil?
          if !seat_assignment.owner.member?(seat_assignment.assigning_user)
            GitHub.logger.info(
              "Assigning user is no longer a member of the #{seat_assignment.owner_type}",
              "code.function": "insert_seats",
              "code.namespace": "Copilot::SeatAssignments::SeatCreation",
              "gh.copilot.seat_assignment.id": seat_assignment.id,
              "gh.copilot.seat_assignment.assigning_user_id": seat_assignment.assigning_user_id,
            )
            nil
          else
            seat_assignment.assigning_user
          end
        end
        actor
      end
    end
  end
end
