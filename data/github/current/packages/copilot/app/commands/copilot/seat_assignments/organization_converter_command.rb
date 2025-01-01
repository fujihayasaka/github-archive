# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatAssignments
    class OrganizationConverterCommand < Command

      include SeatCreation

      # Sets up the command and makes sure it's for an Organization and that the Organization is the organization assigning
      sig { params(seat_assignment: Copilot::SeatAssignment).void.checked(:always).on_failure(:raise) }
      def initialize(seat_assignment)
        valid_assignment = ensure_convertible!(seat_assignment, :ORGANIZATION)

        return if valid_assignment.nil?

        @seat_assignment = T.let(valid_assignment, Copilot::SeatAssignment)
        @owner           = T.let(@seat_assignment.owner, ::Organization)
      end

      # This will load up any existing seats for the members of this Organization (we don't do multiple seats per user)
      #
      # This is intended to be idempotent, so it can be run multiple times without causing any issues
      #
      # At the end of this, we should have Copilot::Seat records for all members of the organization pointing at the seat assignment
      # and there should be no other SeatAssignments owned by this organization
      #
      # This has a number of steps:
      # 1. Load the members of the organization
      # 2. Load the existing seats for the members of the organization (regardless of assignable type)
      # 3. Find the difference between the members of the organization and the existing seats (these are the users needed to be assigned seats)
      # 4. Create the seats for the users that need them
      # 5. Instrument the assignment conversion
      # 6. Update the existing seats and point them to THIS organization seat assignment
      # 7. Check for any seats that are pointing to this organization that are not members of this organization
      # 8. Destroy any other seats that are not this one
      sig { override.void }
      def perform
        seat_assignment_id = @seat_assignment.id

        GitHub.logger.with_named_tags(
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.org.id" => @owner.id,
          "gh.copilot.seat_assignment.id" => seat_assignment_id,
        ) do
          # Try to get a lock on the organization to prevent multiple conversions from happening at the same time
          lock do
            # Load the members of the organization (that are NOT suspended)
            org_member_ids = ::User.where(id: @owner.member_ids).where(suspended_at: nil).pluck(:id).to_set
            GitHub.logger.info("Loaded list of current organization members", "gh.copilot.org.members.count" => org_member_ids.count)

            # Load the existing seats for the members of the organization
            # we want to get the existing seats, regardless of assignable type, for the members of this organization
            # we want to make sure that we don't reinsert them. it's okay if we do because the deduplication job will take care of it
            # use Sets because the `-`` method is magical
            other_assignment_seats = Copilot::Seat.for_assigned_user_and_owner(org_member_ids.to_a, @owner)
            existing_assigned_users = other_assignment_seats.pluck(:assigned_user_id).uniq.to_set

            # Find the difference between the members of the organization and the existing seats (these are the users needed to be assigned seats)
            # using Set's `-` method to find the difference (this means difference will hold the members of org_member_ids that are not in existing_assigned_users)
            difference = org_member_ids - existing_assigned_users

            # let's log this for posterity
            GitHub.logger.with_named_tags(
              "gh.copilot.other_assignment_seats.count" => other_assignment_seats.count,
              "gh.copilot.existing_assigned_users.count" => existing_assigned_users.count,
              "gh.org.member_count" => org_member_ids.count,
              "gh.copilot.difference.count" => difference.count,
            ) do
              if difference.empty?
                # There are no new seats to be created
                GitHub.logger.info("No new seats need to be created")
                GitHub.dogstats.increment("copilot.seat_assignment_conversion.skipped", tags: ["type:organization", "reason:no_difference"])
              else
                # Create the seats for the users that need them
                GitHub.logger.info("New seats need to be created")
                seats_to_insert = difference.map do |user_id|
                  {
                    copilot_seat_assignment_id: seat_assignment_id,
                    organization_id: @owner.id,
                    assigned_user_id: user_id,
                  }
                end

                insert_seats(seats_to_insert, @seat_assignment)

                # log all of this
                Copilot::Instrumenter.instrument_copilot_for_business_assignment_conversion(
                  @seat_assignment,
                  existing_assigned_users.count,
                  difference.count,
                  seats_to_insert.count
                )

                GitHub.dogstats.histogram("copilot.seat_assignment_conversion.difference", difference.count, tags: ["type:organization"])
                GitHub.dogstats.histogram("copilot.seat_assignment_conversion.inserting", seats_to_insert.count, tags: ["type:organization"])
                GitHub.logger.info("Inserted new seats for organization members")
              end

              # we've reached here which means that we've created the seats for the members of the organization who didn't have them
              # Get any other existing seats (for member ids) and point them to THIS organization seat assignment
              GitHub.logger.info("Updating other seats to point to this seat assignment")
              with_write do
                other_assignment_seats.update_all(copilot_seat_assignment_id: seat_assignment_id, updated_at: Date.current)
              end

              # so a weird thing can happen (although it's a bug and rare) where a seat can be pointing at a seat assignment owned
              # by the organization but the user is not a member of the organization.
              # we most likely errored out or something when we handled an event and didn't clean up properly
              # Check for any seats that are pointing to this organization that are not members of this organization
              owner_seats = Copilot::Seat.for_owner(@owner) # this is the list of seats that are pointed at seat assignments owned by this organization
              organization_seat_assigned_user_ids = owner_seats.pluck(:assigned_user_id).to_set # the assigned users
              org_member_ids = @owner.member_ids.to_set # the members of the organization

              to_be_deleted = organization_seat_assigned_user_ids - org_member_ids

              if to_be_deleted.any?
                GitHub.logger.with_named_tags(
                  "gh.copilot.to_be_deleted_count" => to_be_deleted.count,
                ) do
                  GitHub.dogstats.histogram("copilot.seat_assignment_conversion.to_be_deleted", to_be_deleted.count, tags: ["type:organization"])
                  with_write do
                    seats_to_be_deleted = owner_seats.select { |seat| to_be_deleted.include?(seat.assigned_user_id) }

                    message = "Found seats that are pointing to this organization but are not members of the organization"
                    GitHub.logger.error(message)

                    # we're gonna tell a grownup about this
                    Copilot::ErrorReporter.report!(
                      Copilot::Errors::SeatCreationError.new(message),
                      extra_details: {
                        "gh.copilot.seat_assignment.owner.id" => @owner.id,
                        "gh.copilot.seat_assignment.owner.type" => @owner.class.name,
                        "gh.copilot.seat_assignment.id" => seat_assignment_id,
                        "gh.copilot.seat.pending_deleted_ids" => seats_to_be_deleted.map(&:id),
                      }
                    )

                    seats_to_be_deleted.each do |seat|
                      GitHub.logger.error(
                        "Deleting seat for user that is not a member of the organization",
                        "gh.copilot.seat.id" => seat.id,
                        "gh.copilot.seat.assigned_user_id" => seat.assigned_user_id,
                        "gh.copilot.seat_assignment.id" => seat.copilot_seat_assignment_id,
                      )
                      seat.destroy!
                    end
                  end
                end
              end

              # Destroy any other seat assignments for this owner that are not this one since organization seat assignments
              # are the top dog, king of the hill, head honcho, etc.
              GitHub.logger.info("Destroying other seat assignments for this owner that are not this one")
              with_write do
                Copilot::SeatAssignment.for_owner(@owner).where.not(id: seat_assignment_id).destroy_all
              end

              Copilot::SeatManagement::OrganizationDeduplicateJob.perform_later(@owner.id)
            end
          end
        end
      end

      sig do
        type_parameters(:A)
          .params(block: T.proc.returns(T.type_parameter(:A)))
          .returns(T.type_parameter(:A))
      end
      def lock(&block)
        lock_key = "organization-converter-command-#{@owner.id}"

        restraint = GitHub::Restraint.new
        restraint.lock!(lock_key, 1, 5.minutes) do
          block.call
        end
      end
    end
  end
end
