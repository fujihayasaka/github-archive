# typed: strict
# frozen_string_literal: true

module Copilot
  class PendingSeatAssignmentsJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    locked_by timeout: 30.seconds, key: DEFAULT_LOCK_PROC
    schedule interval: 1.hour, condition: -> { GitHub.copilot_for_business_enabled? }
    gate_with_feature_flag :copilot_seat_assignment_job
    exempt_from_tenant_context_requirement

    DAILY_RUN_HOUR = 23
    LAST_ID_KEY = "copilot_pending_seat_assignments_job.maint.id"
    MAX_RUNTIME = 60.0
    BATCH_SIZE = 10_000

    sig { params(run_now: T::Boolean).void }
    def perform(run_now: false)
      # return early unless this job is running in the last hour of the day utc
      unless run_now || Time.current.utc.hour == DAILY_RUN_HOUR
        return
      end
      GitHub.logger.info("Starting Copilot::PendingSeatAssignmentsJob", "code.function" => "perform")

      end_at = Time.now.to_f + MAX_RUNTIME
      last_checked_record_id = Copilot::KV.store.get(LAST_ID_KEY).value { "0" }.to_i
      while Time.now.to_f < end_at
        # Load the next batch.
        records = Copilot::SeatAssignment.pending_cancellation_today.where("id > ?", last_checked_record_id).order(:id).limit(BATCH_SIZE)

        # We're at the end of the table (or the table is empty).
        # Stop processing, and let the next pass through this job start over.
        if records.empty?
          with_write { Copilot::KV.store.set(LAST_ID_KEY, "0") }
          GitHub.logger.info("Copilot::PendingSeatAssignmentsJob - No records found", "code.function" => "perform")
          return
        end

        process_records(records)

        # Record our progress.
        last_checked_record_id = T.must(records.last).id
        with_write { Copilot::KV.store.set(LAST_ID_KEY, last_checked_record_id.to_s) }
      end
      # If we exit the loop because we ran out of time, queue up another job to pick up where we left off.
      GitHub.logger.info("Out of time: Queuing up another Copilot::PendingSeatAssignmentsJob", "code.function" => "perform")
      PendingSeatAssignmentsJob.perform_later(run_now: true)
    end

    sig { params(records: ActiveRecord::Relation).void }
    def process_records(records)
      count = 0
      records.each do |seat_assignment|
        count += 1
        Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_later(seat_assignment.id)
      end
      GitHub.dogstats.count("copilot.pending_seat_assignments_job.to_be_cancelled", count)
      GitHub.logger.info("Processed batch of Copilot::PendingSeatAssignmentsJob", "code.function" => "process_records", "gh.copilot.seat_assignments.count" => count)
    end
  end
end
