# typed: true
# frozen_string_literal: true

class ArchiveDanglingForksJob < ApplicationJob
  use_primaries ApplicationRecord::Repositories

  queue_as :archive_dangling_forks
  retry_on_dirty_exit

  BATCH_SIZE = 75_000

  # Only one of these jobs should run at any given time.
  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  exempt_from_tenant_context_requirement

  # Perform a throttled archive of forks in which the fork owner no longer
  # has permission on the source repository.
  # https://github.com/github/security/issues/2826
  #
  def perform(start = 0, _opts = nil) # will remove _opts after merging https://github.com/github/github/pull/150582
    unless GitHub.enterprise?
      finish = start + BATCH_SIZE
      GitHub.context.push(job: "ArchiveDanglingForks") do
        Audit.context.push(job: "ArchiveDanglingForks") do
          # `job` is set in context to assist with structured logging
          query = DataQuality::RepositoryNetwork::DanglingForks.new(clean: true, start: start, finish: finish)
          query.run
          ArchiveDanglingForksJob.perform_later(finish + 1) if finish < query.max_id
        end
      end
    end
  end
end
