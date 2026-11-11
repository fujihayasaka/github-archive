# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatAssignments
    class BusinessTeamConverterCommand < Command
      include Copilot::SeatManagement::SeatAssignmentHelpers
      include SeatCreation

      # Sets up the command and makes sure it's for a Team and has an Organization
      sig { params(seat_assignment: Copilot::SeatAssignment).void.checked(:always).on_failure(:raise) }
      def initialize(seat_assignment)
        valid_assignment = ensure_convertible!(seat_assignment, :BUSINESS_TEAM)

        @seat_assignment = T.let(valid_assignment, T.nilable(Copilot::SeatAssignment))
        @owner           = T.let(valid_assignment&.owner, ::Business)
        @assigned_team   = T.let(valid_assignment&.assignable, ::BusinessTeam)
      end

      # This is intended to run when a Business Team SeatAssignment is created ONLY. Any updates to the Business Team members will not trigger this command.
      # This will load up any existing seats for the members of this Team (we don't do multiple seats per user)
      #
      # This is intended to be idempotent, so if can be run multiple times without causing any issues.
      #
      # At the end of this, we should have Copilot::Seat records for all members of the Team pointing at the seat assignment
      #
      # This has a number of steps:
      # 1. Load the members of the team
      # 2. Load the existing seats for the members of the team
      # 3. Find the difference between the members of the team and the existing seats (these are the users needed to be assigned seats)
      # 4. Create the seats for the users that need them
      # 5. Instrument the seat assignment conversion
      # 6. Update the existing seats and point them to THIS team seat assignment
      sig { override.void }
      def perform
        seat_assignment_id = @seat_assignment&.id

        GitHub.logger.with_named_tags(
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.business.id" => @owner.id,
          "gh.copilot.seat_assignment.id" => seat_assignment_id,
          "gh.business_team.id" => @assigned_team.id,
          ) do

          if @seat_assignment.nil?
            GitHub.logger.info("Seat assignment is nil, skipping")
            return
          end

          if @seat_assignment.pending_cancellation?
            GitHub.logger.info("Seat assignment is pending cancellation, skipping")
            return
          end

          # Try to get a lock on the team to prevent multiple conversions from happening at the same time
          lock do
            # Load the members of the team - this returns all of them whether they are suspended or not
            team_member_ids = @assigned_team.member_ids.to_set

            # filter out the suspended users
            suspended_team_member_ids = ::User.where(id: team_member_ids).where.not(suspended_at: nil).pluck(:id).to_set

            team_member_ids = team_member_ids - suspended_team_member_ids

            GitHub.logger.info(
              "Loaded list of current team members",
              "gh.copilot.team_member_count" => team_member_ids.count,
              "gh.copilot.suspended_team_member_count" => suspended_team_member_ids.count,
            )

            # we want to get the existing seats, regardless of assignable type, for the members of this team
            existing_seats_for_members = Copilot::Seat.for_assigned_user_and_owner(team_member_ids.to_a, @owner)
            existing_assigned_users = existing_seats_for_members.pluck(:assigned_user_id).uniq.to_set

            # if a user belongs to multiple teams that are assigned, it doesn't matter which team seat assignment their seat is pointed at
            # so we can just update the existing seats to point at this team seat assignment. We also want to do this in case a user already
            # has a User seat assignment. This does not trigger callbacks or change updated_at on the seats.
            if existing_seats_for_members.any?
              with_write do
                existing_seats_updated_count = existing_seats_for_members.update_all(copilot_seat_assignment_id: seat_assignment_id, updated_at: Date.current)

                GitHub.logger.info("Updated existing seats to point at this BusinessTeam SeatAssignment",
                  "gh.copilot.existing_seats_updated" => existing_seats_updated_count,
                  "gh.copilot.seat.ids" => existing_seats_for_members.pluck(:id))

                GitHub.dogstats.histogram("copilot.seat_assignment_conversion.existing_seats_updated", existing_seats_updated_count, tags: ["type:business_team"])
              end
            end

            # Find the difference between the members of the team and the existing seats (these are the users needed to be assigned seats)
            # using set difference to find the users that need to be assigned seats
            difference = team_member_ids - existing_assigned_users

            # let's log this
            GitHub.logger.with_named_tags(
              "gh.copilot.existing_seats_for_members.count" => existing_seats_for_members.count,
              "gh.copilot.existing_assigned_users.count" => existing_assigned_users.count,
              "gh.business_team.member_count" => team_member_ids.count,
              "gh.copilot.difference.count" => difference.count,
            ) do
              if difference.empty?
                # no new seats need to be created
                GitHub.logger.info("No new seats need to be created")
                GitHub.dogstats.increment("copilot.seat_assignment_conversion.skipped", tags: ["type:business_team", "reason:no_difference"])
              else
                # Create the seats for the users that need them
                GitHub.logger.info("New seats need to be created")
                seats_to_insert = difference.map do |user_id|
                  {
                    copilot_seat_assignment_id: seat_assignment_id,
                    organization_id: nil, # this is an Business Team, so no organization
                    assigned_user_id: user_id,
                  }
                end

                insert_seats(seats_to_insert, @seat_assignment)

                # This does not appear in the user-facing audit log
                Copilot::Instrumenter.instrument_copilot_for_business_assignment_conversion(
                  @seat_assignment,
                  existing_assigned_users.count,
                  difference.count,
                  seats_to_insert.count
                )

                GitHub.dogstats.histogram("copilot.seat_assignment_conversion.difference", difference.count, tags: ["type:business_team"])
                GitHub.dogstats.histogram("copilot.seat_assignment_conversion.inserting", seats_to_insert.count, tags: ["type:business_team"])
                GitHub.logger.info("Inserted new seats for team members")
              end
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
        lock_key = "copilot-business-team-converter-command-#{@owner.id}-#{@assigned_team.id}"

        restraint = GitHub::Restraint.new
        restraint.lock!(lock_key, 1, 5.minutes) do
          block.call
        end
      end
    end
  end
end
