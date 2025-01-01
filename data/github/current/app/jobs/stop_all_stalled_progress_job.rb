# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This regularly scheduled job looks for stalled progress and stops all of it.
class StopAllStalledProgressJob < ApplicationJob
  queue_as :stop_all_stalled_progress_job
  schedule interval: 1.minute
  retry_on_dirty_exit

  # This job is exempt from tenant scoping because:
  # - It does not handle tenant-scoped data.
  # - Its primary data store is Redis.
  # - It is responsible for cleaning up *internal* progress tracking records.
  exempt_from_tenant_context_requirement

  def perform
    GitHub::Progress::Server.stop_all_stalled
  end
end
