# typed: true
# frozen_string_literal: true

# The ProcessSystemEvent command is invoked by the CodespacesProcessSystemEventJob. This job
# is enqueued under many different scenarios and event sources. Some of the events are repository access changes,
# Codespaces access changes and billing pipeline detection of inaccessible codespaces.
module Codespaces
  class ProcessSystemEvent < Command
    attr_reader :codespaces, :error_reporter, :transfer_billable_owner, :deletion_reason

    # Perform the job after the waiting period to allow for codespaces which
    # were inaccessible to become accessible again.
    CLEAN_UP_INACCESSIBLE_CODESPACE_WAITING_PERIOD = 7.days

    def initialize(codespaces, error_reporter: Codespaces::ErrorReporter, transfer_billable_owner: true, deletion_reason: Codespace.deletion_reasons[:process_system_event])
      @codespaces = codespaces
      @error_reporter = error_reporter
      @transfer_billable_owner = transfer_billable_owner
      @deletion_reason = deletion_reason
    end

    def perform
      codespaces.each do |codespace|
        Codespaces::TransferBillableOwner.call(codespace) if transfer_billable_owner

        if !codespace.accessible?
          Codespaces::CleanUpInaccessibleJob.perform_after_waiting_period(waiting_period: CLEAN_UP_INACCESSIBLE_CODESPACE_WAITING_PERIOD, codespace: codespace, reason: deletion_reason)
          CodespacesSuspendEnvironmentJob.perform_later(codespace: codespace, ignore_deleted: true)
        end
      rescue => e # rubocop:todo Lint/RescueException
        error_reporter.push(codespace_id: codespace.id)
        error_reporter.report(e)
      end
    end
  end
end
