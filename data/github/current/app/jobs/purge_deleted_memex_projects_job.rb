# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PurgeDeletedMemexProjectsJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt

  queue_as :purge_deleted_memex_projects
  schedule interval: 1.hour
  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
  retry_on_dirty_exit

  BATCH_SIZE = 100
  MINIMUM_AGE_TO_PURGE = 90.days

  exempt_from_tenant_context_requirement

  # start_time: The time that the first job of the batch was initially kicked off. Used to track the
  #             total duration across all batches.
  def perform(start_time = initially_enqueued_at)
    GitHub.dogstats.count("purge_deleted_memex_projects.deleted_projects_count", total_deleted_projects)

    projects_batch = find_projects_to_delete
    projects_batch.each do |project|
      MemexProject.throttle do
        with_write { project.destroy! }
      end
    end

    # If we've purged all deleted projects, mark the total time across all batches,
    # otherwise, queue the next batch.
    if projects_batch.empty?
      duration = Time.now.utc - start_time
      GitHub.dogstats.distribution("purge_deleted_memex_projects.dist.duration", duration)
    else
      PurgeDeletedMemexProjectsJob.perform_later(start_time)
    end
  end

  def find_projects_to_delete
    MemexProject.deleted_projects
      .where("deleted_at < ?", MINIMUM_AGE_TO_PURGE.ago)
      .limit(BATCH_SIZE)
  end

  def total_deleted_projects
    MemexProject.deleted_projects.count
  end
end
