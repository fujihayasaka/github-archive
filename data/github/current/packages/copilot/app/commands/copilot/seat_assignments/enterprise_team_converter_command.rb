# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatAssignments
    class EnterpriseTeamConverterCommand < Command

      include SeatCreation

      sig { params(seat_assignment: Copilot::SeatAssignment).void }
      def initialize(seat_assignment)
        # Make sure it's for an EnterpriseTeam and has an Owner
        valid_assignment = ensure_convertible!(seat_assignment, :ENTERPRISE_TEAM)
        return if valid_assignment.nil? # if we didn't get a valid assignment, we're done

        @seat_assignment = T.let(valid_assignment, Copilot::SeatAssignment)
        @owner           = T.let(seat_assignment.owner, ::Business)
        @assigned_team   = T.let(seat_assignment.assignable, ::EnterpriseTeam)
      end

      # This will load up any existing seats for the members of this Team (we don't do multiple seats per user)
      # 1. Load up the members of the EnterpriseTeam
      # 2. Find any seats for these members (even if the Seats point to non-EnterpriseTeam SeatAssignments which shouldn't happen)
      # 3. Use Sets to remove that already have seats
      # 4. If there are any left, create a new seat for them
      # 5. Instrument that we converted this
      # 6. Find any Seats associated with this SeatAssignment that are NOT members of this EnterpriseTeam and remove them
      #
      # This is intended to now be idempotent, so if it's run multiple times, it should not create duplicate seats and should clean up itself
      #
      # When the command completes, all members of the EnterpriseTeam at the time this command is called have a seat
      sig { override.void }
      def perform
        GitHub.logger.with_named_tags(
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.business.id" => @owner.id,
          "gh.copilot.seat_assignment.id" => @seat_assignment.id,
          "gh.enterprise_team.id" => @assigned_team.id,
          ) do
          lock do
            # Load up the team members for the EnterpriseTeam
            team_member_ids = @assigned_team.member_user_ids.to_set
            suspended_team_member_ids = ::User.where(id: team_member_ids).where.not(suspended_at: nil).pluck(:id).to_set

            team_member_ids = team_member_ids - suspended_team_member_ids

            GitHub.logger.info(
              "Loaded list of current team members",
              "gh.copilot.team_member_count" => team_member_ids.count,
              "gh.copilot.suspended_team_member_count" => suspended_team_member_ids.count,
            )

            # get the team members who already have seats with this business (it should ONLY be for an EnterpriseTeam but this is the Wild West)
            # we want to get the existing seats, regardless of assignable type, for the members of this team
            existing_seats_for_members = Copilot::Seat.for_assigned_user_and_owner(team_member_ids.to_a, @owner)
            existing_assigned_users = existing_seats_for_members.pluck(:assigned_user_id).uniq.to_set

            with_write do
              # if any member of the team has an existing seat, we can associate them with the SeatAssignment being converted instead.
              # if we've gotten here, we've called ensure_convertible! and we know the SeatAssignment we're converting is not pending cancellation
              if @owner.feature_enabled?(:ent_team_job_redirect_existing_seats)
                existing_seats_updated_count = existing_seats_for_members.update_all(copilot_seat_assignment_id: @seat_assignment.id, updated_at: Date.current)
                if existing_seats_updated_count
                  GitHub.logger.info("Updated existing seats to point at this EnterpriseTeam SeatAssignment",
                                    "gh.copilot.existing_seats_updated" => existing_seats_updated_count,
                                    "gh.copilot.seat.ids" => existing_seats_for_members.pluck(:id),
                                    "gh.copilot.seat_assignment.id" => @seat_assignment.id)
                end
                GitHub.dogstats.histogram("copilot.seat_assignment_conversion.existing_seats_updated", existing_seats_updated_count, tags: ["type:enterprise_team"])
              end

              # We want to destroy seats for deprovisioned users
              if suspended_team_member_ids.count > 0
                GitHub.logger.info("Suspended team members found, destroying their seats")
                seats = Copilot::Seat.for_assigned_user_and_owner(suspended_team_member_ids.to_a, @owner).destroy_all
                GitHub.logger.info("Destroyed seats for suspended team members", "gh.copilot.seats_destroyed" => seats.count)
              end
            end

            # Calculate the difference between the team members (minus supended users) and the existing assigned users
            difference = team_member_ids - existing_assigned_users

            GitHub.logger.with_named_tags(
              "gh.copilot.existing_seats_for_members.count" => existing_seats_for_members.count,
              "gh.copilot.existing_assigned_users.count" => existing_assigned_users.count,
              "gh.enterprise_team.member_count" => team_member_ids.count,
              "gh.copilot.difference.count" => difference.count,
            ) do
              if difference.empty?
                # yay we can get a cookie
                GitHub.logger.info("No new seats need to be created")
                GitHub.dogstats.increment("copilot.seat_assignment_conversion.skipped", tags: ["type:enterprise_team", "reason:no_difference"])
              else
                # we have to wait for our cookie
                GitHub.logger.info("Processing enterprise team members")

                seats_to_insert = difference.map do |user_id|
                  {
                    copilot_seat_assignment_id: @seat_assignment.id,
                    # this is an EnterpriseTeam, so no organization
                    organization_id: nil, # TODO: Deprecate this column
                    assigned_user_id: user_id,
                  }
                end

                # insert the seats passing owner because this is an EnterpriseTeam
                insert_seats(seats_to_insert, @seat_assignment)

                Copilot::Instrumenter.instrument_copilot_for_business_assignment_conversion(
                  @seat_assignment,
                  existing_assigned_users.count,
                  difference.count,
                  seats_to_insert.count
                )

                GitHub.dogstats.histogram("copilot.seat_assignment_conversion.difference", difference.count, tags: ["type:enterprise_team"])
                GitHub.dogstats.histogram("copilot.seat_assignment_conversion.inserting", seats_to_insert.count, tags: ["type:enterprise_team"])

                GitHub.logger.info("Processed enterprise team members")
              end

              to_be_deleted = Copilot::Seat.
                where(copilot_seat_assignment_id: @seat_assignment.id).
                where.not(assigned_user_id: team_member_ids)

              # unlike any other seat assignment, we need to delete seats that are not associated with the team members
              to_be_deleted_count = to_be_deleted.count

              GitHub.dogstats.histogram("copilot.seat_assignment_conversion.to_be_deleted", to_be_deleted_count, tags: ["type:enterprise_team"])

              if to_be_deleted_count.zero?
                GitHub.logger.info("No seats need to be deleted")
              else
                GitHub.logger.info(
                  "Deleting seats not associated with EnterpriseTeam members",
                  "gh.copilot.to_be_deleted.count" => to_be_deleted_count,
                )

                with_write do
                  # delete the seats that don't have members associated with them
                  deleted = to_be_deleted.inject(0) do |count, seat|
                    if seat.destroy
                      Copilot::Instrumenter.send_to_hydro(
                        Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED, {
                          user: nil,
                          organization: nil,
                          seat: seat,
                          actor: @seat_assignment.assigning_user,
                          details: {}
                        },
                      )

                      count += 1
                    end
                    count
                  end

                  GitHub.logger.info(
                    "Deleted seats not associated with EnterpriseTeam members",
                    "gh.copilot.to_be_deleted.count" => to_be_deleted_count,
                    "gh.copilot.deleted_seats.count" => deleted,
                  )
                end
              end
            end
          end

          GitHub.logger.info("Finished processing enterprise team members")
        end
      end

      sig do
        type_parameters(:A)
          .params(block: T.proc.returns(T.type_parameter(:A)))
          .returns(T.type_parameter(:A))
      end
      def lock(&block)
        lock_key = "enter-team-converter-command-#{@owner.id}-#{@assigned_team.id}"

        restraint = GitHub::Restraint.new
        restraint.lock!(lock_key, 1, 5.minutes) do
          block.call
        end
      end
    end
  end
end
