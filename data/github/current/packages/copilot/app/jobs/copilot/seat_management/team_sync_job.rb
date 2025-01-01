# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class TeamSyncJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      schedule interval: 2.hours, condition: -> { GitHub.copilot_for_business_enabled? }
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag %i(copilot_seat_assignment_job copilot_team_sync_job)

      exempt_from_tenant_context_requirement

      # We need this job for a few reasons, the main one being that sometimes when users are added to a team
      # when they accept an OrganizationInvitation, a race condition occurs that leads to the seat not being created.
      # This will also take care of any other reason that the number of seats for members of a team falls out of sync with the
      # number of members eligible for seats on the team, such as instances where team membership changes occurred
      # before seat hierarchy fixes were made and seats were mistakenly cancelled

      sig { void }
      def perform
        GitHub.logger.info("Starting TeamSyncJob")

        GitHub.dogstats.distribution_time("copilot.seat_management.team_sync_job.convert_assignments.duration") do
          with_read do
            # let's make sure we're not in the cooldown period for the seat assignment; the DelayedConverterJob will run once that time has passed
            assignments_to_convert = [:TEAM, :ENTERPRISE_TEAM].map do |type|
              Copilot::SeatAssignment
                .includes(:assignable)
                .where(assignable_type: type.to_s.split("_").map(&:capitalize).join)
                .where("created_at < ?", T.must(Copilot::COPILOT_SEAT_COOLDOWN_PERIODS[type]).ago.utc)
                .where.not(assignable: nil)
            end.reduce(:or)

            GitHub.dogstats.count("copilot.seat_management.team_sync_job.assignments_to_convert", assignments_to_convert.count)

            # get all SeatAssignments of type Team or EnterpriseTeam in batches and convert them
            assignments_to_convert.find_in_batches(batch_size: 1000) do |batch|
              batch.each do |seat_assignment|

                # convert_to_seats is idempodent and will call the appropriate ConverterCommand based on the assignable type.
                # The ConverterCommands only create new seats for users that don't already have a seat,
                # prevent suspended users from getting a seat, and destroys seats for suspended users if they exist
                #
                # To avoid making too many queries, we'll let the ConverterCommand determine and log how many seats will need to be created (if any).
                # A side effect of re-converting a team, even if it doesn't require seats to be created, is that any members with seats pointing to
                # other SeatAssignments will have their seats repointed to the SeatAssignment being converted.
                result = with_write do
                  seat_assignment.convert_to_seats
                end

                if result.error
                  GitHub.logger.info(
                    "Failed to convert team seat assignment",
                    {
                      "gh.copilot.seat_assignment.id" => seat_assignment&.id,
                      "gh.copilot.seat_assignment.owner.id" => seat_assignment&.owner_id,
                      "gh.copilot.seat_assignment.owner.type" => seat_assignment&.owner_type,
                      "gh.copilot.seat_assignment.assignable.id" => seat_assignment&.assignable_id,
                      "gh.copilot.seat_assignment.assignable.type" => seat_assignment&.assignable_type,
                      "gh.copilot.seat_assignment.symbolized_assignable_type" => seat_assignment&.symbolized_assignable_type
                    }
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end
