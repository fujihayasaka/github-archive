# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatAssignments
    class EnterpriseTeamConverterCommand < Command
      include Copilot::SeatManagement::SeatAssignmentHelpers
      include SeatCreation

      STATS_KEY = "copilot.enterprise_team_converter_command"

      sig { params(seat_assignment: Copilot::SeatAssignment).void }
      def initialize(seat_assignment)
        # Make sure it's for an EnterpriseTeam and has an Owner
        valid_assignment = ensure_convertible!(seat_assignment, :ENTERPRISE_TEAM)

        @seat_assignment    = T.let(valid_assignment, T.nilable(Copilot::SeatAssignment))
        @owner              = T.let(valid_assignment&.owner, ::Business)
        @assigned_team_id   = T.let(valid_assignment&.assignable_id, Integer)
      end

      # This command is called any time there's a membership update on an EnterpriseTeam, so it does a bunch of things:
      # 1. Load the members of the team
      # 2. handles destroying/revoking access for suspended users
      # 3. handles destroying/revoking access or repointing seats for users who are not members of the team anymore
      # 4. handles destroying/revoking access for users who were destroyed
      # 5. handles repointing seats for users who are members of the team but have existing seats on other teams
      # 6. handles creating seats for users who are members of this team but have no seat (actual conversion)
      # This is intended to now be idempotent, so if it's run multiple times, it should not create duplicate seats and should clean up itself
      sig { override.void }
      def perform
        GitHub.logger.with_named_tags(
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.business.id" => @owner.id,
          "gh.copilot.seat_assignment.id" => @seat_assignment&.id,
          "gh.enterprise_team.id" => @assigned_team_id,
          ) do
          if @seat_assignment.nil?
            GitHub.logger.info("Seat assignment is nil, skipping")
            return
          end

          if @seat_assignment.pending_cancellation?
            GitHub.logger.info("Seat assignment is pending cancellation, skipping")
            return
          end

          lock do
            should_revoke_access = @owner.feature_enabled?(:copilot_revokable_access)

            assigned_team = ::EnterpriseTeam.find_by(id: @assigned_team_id)

            # team was destroyed; we should never get here because the EnterpriseTeamJob should have taken care of
            # things instead
            if assigned_team.nil?
              GitHub.logger.info("EnterpriseTeam no longer exists")
              report_error(Copilot::Errors::SeatAssignmentError.new("Attempting to convert SeatAssignment for destroyed EnterpriseTeam"))
              return
            end

            # Load up the team members for the EnterpriseTeam
            team_member_ids = assigned_team.member_user_ids.to_set

            # Find all users in the team that are suspended.  This could only really happen if the team is directly managed and a user was
            # suspended somehow.  For IdP managed enterprise teams, users are both suspended/deprovisioned AND removed from the team.
            suspended_team_member_ids = ::User.where(id: team_member_ids).where.not(suspended_at: nil).pluck(:id).to_set
            unsuspended_team_member_ids = team_member_ids - suspended_team_member_ids
            deleted_user_ids = unsuspended_team_member_ids.inject([]) do |memo, user_id|
              user = ::User.find_by(id: user_id)
              memo << user_id if user.nil? || user.deleted?
              memo
            end.to_set

            GitHub.logger.info(
              "Loaded list of current unsuspended team members",
              "gh.copilot.team_member_count" => unsuspended_team_member_ids.count,
              "gh.copilot.suspended_team_member_count" => suspended_team_member_ids.count,
            )

            # We want to destroy seats for deprovisioned (suspended) users unless copilot_revokable_access is enabled
            suspended_user_seats = Copilot::Seat.for_assigned_user_and_owner(suspended_team_member_ids.to_a, @owner)
            handle_suspended_user_seats(suspended_user_seats, @seat_assignment, should_revoke_access)

            # get the team members WHO ARE NOT SUSPENDED who already have seats in this enterprise
            existing_seats_for_members = Copilot::Seat.for_assigned_user_and_owner(unsuspended_team_member_ids.to_a, @owner)
            existing_assigned_user_ids = existing_seats_for_members.pluck(:assigned_user_id).uniq.to_set

            # we want to repoint any existing seats for members of the team to this assignment
            handle_existing_seats_for_members(existing_seats_for_members, @seat_assignment)

            # Calculate the difference between the unsuspended team members and the existing assigned users (minus the deleted users)
            # This will give us the users who are members of the team but do not have a Seat yet
            user_ids_for_seat_creation = unsuspended_team_member_ids - existing_assigned_user_ids - deleted_user_ids

            GitHub.logger.with_named_tags(
              "gh.copilot.existing_seats_for_members.count" => existing_seats_for_members.count,
              "gh.copilot.existing_assigned_users.count" => existing_assigned_user_ids.count,
              "gh.enterprise_team.member_count" => unsuspended_team_member_ids.count,
              "gh.copilot.difference.count" => user_ids_for_seat_creation.count,
            ) do
              if user_ids_for_seat_creation.empty?
                # cool, all members have seats already
                GitHub.logger.info("No new seats need to be created for enterprise team members")
                GitHub.dogstats.increment("copilot.seat_assignment_conversion.skipped", tags: ["type:enterprise_team", "reason:no_difference"])
              else
                seats_to_insert = user_ids_for_seat_creation.map do |user_id|
                  {
                    copilot_seat_assignment_id: @seat_assignment.id,
                    organization_id: nil, # this is an EnterpriseTeam, so no organization
                    assigned_user_id: user_id,
                  }
                end

                insert_seats(seats_to_insert, @seat_assignment)

                Copilot::Instrumenter.instrument_copilot_for_business_assignment_conversion(
                  @seat_assignment,
                  existing_assigned_user_ids.count,
                  user_ids_for_seat_creation.count,
                  seats_to_insert.count
                )

                GitHub.dogstats.histogram("copilot.seat_assignment_conversion.difference", user_ids_for_seat_creation.count, tags: ["type:enterprise_team"])
                GitHub.dogstats.histogram("copilot.seat_assignment_conversion.inserting", seats_to_insert.count, tags: ["type:enterprise_team"])

                GitHub.logger.info("Created seats for new enterprise team members")
              end

              # find seats that are pointing at this EnterpriseTeam seat assignment but are not actually members of the enterprise team
              seats_for_non_team_members = Copilot::Seat.
                  where(copilot_seat_assignment_id: @seat_assignment.id).
                  where.not(assigned_user_id: team_member_ids - deleted_user_ids)

              handle_seats_for_non_team_members(seats_for_non_team_members, @seat_assignment, should_revoke_access)
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
        lock_key = "enter-team-converter-command-#{@owner.id}-#{@assigned_team_id}"

        restraint = GitHub::Restraint.new
        restraint.lock!(lock_key, 1, 5.minutes) do
          block.call
        end
      end

      sig { params(suspended_user_seats: ActiveRecord::Relation, seat_assignment: Copilot::SeatAssignment, should_revoke_access: T::Boolean).void }
      def handle_suspended_user_seats(suspended_user_seats, seat_assignment, should_revoke_access)
        with_write do
          if suspended_user_seats.empty?
            GitHub.logger.info("No suspended user seats to process")
          end

          # We want to destroy seats for deprovisioned (suspended) users unless copilot_revokable_access is enabled
          if should_revoke_access
            suspended_user_seats.each do |seat|
              # we need to create a disassociated assignment for the suspended user and point the seat at that instead of deleting it
              disassociate_and_revoke_seat(seat, seat.seat_assignment, :suspended_user_in_enterprise_team, nil)

              GitHub.dogstats.increment("#{STATS_KEY}.suspended_user.access_revoked")
            end
          else
            destroyed_user_seats = suspended_user_seats.destroy_all

            if destroyed_user_seats.count > 0
              GitHub.logger.info("Destroyed seats for suspended enterprise team members", "gh.copilot.seats_destroyed" => destroyed_user_seats.count)
            end
          end
        end
      end

      sig { params(existing_seats_for_members: ActiveRecord::Relation, this_seat_assignment: Copilot::SeatAssignment).void }
      def handle_existing_seats_for_members(existing_seats_for_members, this_seat_assignment)
        user_seats_updated = 0
        enterprise_team_seats_updated = 0

        with_write do
          # if any member of the team who is not suspended has an existing seat, we can associate them with the SeatAssignment being converted instead
          # if we've gotten here, we've called ensure_convertible! and we know the SeatAssignment we're converting is not pending cancellation
          existing_seats_for_members.each do |seat|
            seat_assignment = seat.seat_assignment

            # if the seat is pointing at a User assignment we can repoint the seat at this one and delete that assignmnt.
            # It probably means they were previously removed from all teams and got a disassociated assignment
            # we won't be repointing seats for suspended members because existing_seats_for_members excludes them.
            if seat_assignment.assignable_type == "User"
              if seat_assignment.access_revoked?
                # We're implictly reinstating access, so we just log
                seat_assignment.log_reinstatement(:user_added_to_enterprise_team)
              end

              seat.update(copilot_seat_assignment_id: this_seat_assignment.id)

              GitHub.logger.info("Updated existing seat to point at this EnterpriseTeam SeatAssignment",
                "gh.copilot.original_seat_assignment.id" => seat_assignment.id,
                "gh.user.id" => seat.assigned_user_id)

              user_seats_updated += 1
              # destroy the user assignment the seat was originally pointing to
              seat_assignment.destroy!
            else
              next if seat_assignment.id == this_seat_assignment.id

              # If the seat is pointing at another EnterpriseTeam assignment (i.e. the user is on multiple teams)
              # we can repoint it to this one, we don't care which SeatAssignment their Seat is associated with.
              seat.update(copilot_seat_assignment_id: this_seat_assignment.id)

              GitHub.logger.info("Updated existing seat to point at this EnterpriseTeam SeatAssignment",
                "gh.copilot.original_seat_assignment.id" => seat_assignment.id,
                "gh.user.id" => seat.assigned_user_id)
              enterprise_team_seats_updated += 1
            end

            GitHub.dogstats.count("#{STATS_KEY}.existing_seats_updated", user_seats_updated, tags: ["type:user"]) if user_seats_updated > 0
            GitHub.dogstats.count("#{STATS_KEY}.existing_seats_updated", enterprise_team_seats_updated, tags: ["type:enterprise_team"]) if enterprise_team_seats_updated > 0
          end
        end
      end

      sig { params(seats_for_non_team_members: ActiveRecord::Relation, enterprise_team_seat_assignment: Copilot::SeatAssignment, should_revoke_access: T::Boolean).void }
      def handle_seats_for_non_team_members(seats_for_non_team_members, enterprise_team_seat_assignment, should_revoke_access)
        # We found seats that are pointing at this EnterpriseTeam assignment where the assigned user is not actually members of the enterprise team
        to_be_deleted = 0

        seats_for_non_team_members.each do |seat|
          # check if the seat can be pointed at a different enterprise team and if so, do that
          next if repoint_seat_to_other_team(seat, enterprise_team_seat_assignment)

          # if not, they're not a member of the enterprise anymore, are not a member of any team, or are destroyed; we revoke their access
          if should_revoke_access
            GitHub.logger.info("Seat's assigned user is no longer a member of the enterprise team, disassociating and revoking access", "gh.user.id" => seat.assigned_user_id) unless seat.assigned_user.nil?

            disassociate_and_revoke_seat(seat, seat.seat_assignment, :removed_user_in_enterprise_team, nil)

            GitHub.dogstats.increment("#{STATS_KEY}.removed_user.access_revoked")
          else
            to_be_deleted += 1
            with_write do
              user = seat.assigned_user
              if seat.destroy
                Copilot::Instrumenter.send_to_hydro(
                  Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED, {
                    user: user,
                    organization: nil,
                    seat: seat,
                    actor: enterprise_team_seat_assignment.assigning_user,
                    details: {}
                  },
                ) unless user.nil?
                GitHub.dogstats.increment("#{STATS_KEY}.removed_user.seat_destroyed")
              end
            end

            GitHub.logger.info(
              "Deleted seat for user not associated with EnterpriseTeam",
              "gh.copilot.seat.id" => seat.id,
              "gh.user.id" => seat.assigned_user_id,
            )
          end
        end

        if to_be_deleted > 0
          # all of the converter commands have this but once revokable access is enabled, we shouldn't hit this
          GitHub.dogstats.histogram("copilot.seat_assignment_conversion.to_be_deleted", to_be_deleted, tags: ["type:enterprise_team"])
        end
      end

      sig { params(error: Copilot::Errors::CopilotError, details: T::Hash[Symbol, T.untyped]).void } # rubocop:disable Sorbet/ForbidTUntyped
      def report_error(error,  details = {})
        details = details.merge({
          "gh.enterprise_team.id" => @assigned_team_id,
          "gh.copilot.seat_assignment.id" => @seat_assignment&.id
        })
        GitHub.logger.error(error.message)
        handle_copilot_error(error, details)
      end
    end
  end
end
