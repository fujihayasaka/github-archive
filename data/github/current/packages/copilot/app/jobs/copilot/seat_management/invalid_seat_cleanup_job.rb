# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # This job is responsible for cleaning up any seat assignments that have
    # an owner_id that no longer exists. This can happen if an org or business
    # is deleted and the seat assignment is not cleaned up properly.
    class InvalidSeatCleanupJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      schedule interval: 3.hours, condition: -> { GitHub.copilot_for_business_enabled? }
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_seat_assignment_job

      sig { void }
      def perform
        with_write do
          # Lets make sure that all seat assignments that have an org also have an owner_id, otherwise the rest of this won't work
          Copilot::SeatAssignment.where(owner_id: nil).map(&:make_sure_owner_is_populated!)
        end

        seat_assignment_invalid_org_ids = []
        seat_assignment_invalid_business_ids = []

        # Get all the invalid seat assignment org ids by comparing the owner_ids against actual orgs
        Copilot::SeatAssignment.where.not(owner_id: nil).where(owner_type: "Organization").find_in_batches do |batch|
          seat_assignment_org_owner_ids = batch.pluck(:owner_id).uniq
          org_ids_with_seat_assignments = ::Organization.where(id: seat_assignment_org_owner_ids).pluck(:id)
          seat_assignment_invalid_org_ids.concat(seat_assignment_org_owner_ids - org_ids_with_seat_assignments)
        end

        # Now do the same for businesses
        Copilot::SeatAssignment.where.not(owner_id: nil).where(owner_type: "Business").find_in_batches do |batch|
          seat_assignment_business_owner_ids = batch.pluck(:owner_id).uniq
          business_ids_with_seat_assignments = ::Business.where(id: seat_assignment_business_owner_ids).pluck(:id)
          seat_assignment_invalid_business_ids.concat(seat_assignment_business_owner_ids - business_ids_with_seat_assignments)
        end

        if seat_assignment_invalid_org_ids.any? || seat_assignment_invalid_business_ids.any?
          GitHub.logger.info(
            "SeatAssignment owner ids without a corresponding owner",
            "gh.copilot.seat_assignment.invalid_org_count" => seat_assignment_invalid_org_ids.count,
            "gh.copilot.seat_assignment.invalid_business_count" => seat_assignment_invalid_business_ids.count,
            )

          invalid_seat_assignments = Copilot::SeatAssignment.where(
            owner_id: seat_assignment_invalid_org_ids,
            owner_type: "Organization"
          ).or(
            Copilot::SeatAssignment.where(
              owner_id: seat_assignment_invalid_business_ids,
              owner_type: "Business"
            )
          )

          GitHub.dogstats.distribution_time("copilot.seat_management.invalid_seat_cleanup_job.clean_invalid.duration") do
            invalid_seat_assignments.each do |invalid_seat_assignment|
              GitHub.logger.info(
                "Processing SeatAssignment with invalid owner",
                "gh.copilot.seat_assignment.id" => invalid_seat_assignment.id
              )

              with_write do
                GitHub.logger.info(
                  "Cancelling associated seats",
                  "gh.copilot.seat_assignment.seats.count" => invalid_seat_assignment.seats.count,
                  "gh.copilot.seat_assignment.id" => invalid_seat_assignment.id
                )

                invalid_seat_assignment.seats.each do |seat|
                  seat.cancel!
                end

                GitHub.logger.info(
                  "Destroying SeatAssignment",
                  "gh.copilot.seat_assignment.id" => invalid_seat_assignment.id,
                  "gh.copilot.seat_assignment.owner_id" => invalid_seat_assignment.owner_id,
                  "gh.copilot.seat_assignment.owner_type" => invalid_seat_assignment.owner_type,
                )
                GitHub.dogstats.increment(
                  "copilot.seat_management.invalid_seat_cleanup_job.seat_assignment_destroyed"
                )

                invalid_seat_assignment.destroy!
              end
            end
          end
        end
      end
    end
  end
end
