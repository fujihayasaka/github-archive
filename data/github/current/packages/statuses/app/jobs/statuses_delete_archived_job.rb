# typed: true
# frozen_string_literal: true

class StatusesDeleteArchivedJob < ApplicationJob
  include GitHub::Tracing
  include ChecksJobUtility

  DELETE_BATCH_SIZE = 10
  READ_BATCH_SIZE = 5000

  queue_as :statuses_delete_archived
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Archives a batch of check_suites between a start and end id (inclusive)
  def perform(updated_at_start:, updated_at_end:, concurrent_job_key:)
    raise ArgumentError, "updated_at_start must be provided." unless updated_at_start.present?
    raise ArgumentError, "updated_at_end must be provided." unless updated_at_end.present?
    raise ArgumentError, "concurrent_job_key must be provided." unless concurrent_job_key.present?

    lock! do
      delete_statuses(updated_at_start: updated_at_start, updated_at_end: updated_at_end, concurrent_job_key: concurrent_job_key)
    rescue ActiveRecord::RecordNotFound, StandardError => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      raise e
    end
  end

  private

  # https://thehub.github.com/epd/engineering/products-and-services/dotcom/background-jobs/lockable-jobs/#restraint-locks
  def lock!
    restraint = GitHub::Restraint.new
    lock_key = self.class.name
    max_concurrent_jobs = 6 # Maximum of 6 concurrent jobs
    lock_ttl = 5.minutes
    restraint.lock!(T.must(lock_key), max_concurrent_jobs, lock_ttl) do
      yield
    end
  rescue GitHub::Restraint::UnableToLock
    GitHub.dogstats.increment("checks.delete_archived_job.unable_to_lock", tags: ["job:status"])
    # Skip job if we try to run while lock is held
  end

  def delete_statuses(updated_at_start:, updated_at_end:, concurrent_job_key:)
    total_delete_count = 0

    loop do
      archived_statuses_ready_for_deletion = Status
        .from("statuses FORCE INDEX(index_statuses_on_is_archived_updated_at)")
        .where("is_archived = true")
        .where("updated_at between :updated_at_start AND :updated_at_end", updated_at_start: updated_at_start, updated_at_end: updated_at_end)
        .where("updated_at <= ?", delete_archived_threshold_days.ago)
        .order(id: :asc)
        .limit(READ_BATCH_SIZE)
        .pluck(:repository_id, :id)

      break if archived_statuses_ready_for_deletion.empty?

      repo_id_pairs = group_by_repository_id(archived_statuses_ready_for_deletion)
      repo_id_pairs.each do |repository_id, archived_status_ids|
        archived_status_ids.in_groups_of(DELETE_BATCH_SIZE) do |batch|
          ActiveRecord::Base.connected_to(role: :writing) do
            deleted_count = Status.throttle do
              Status.where(repository_id: repository_id, id: batch).delete_all
            end
            total_delete_count = total_delete_count + deleted_count
          end
        end
      end
    end

    GitHub.dogstats.count("checks.delete_archived_job.deleted", total_delete_count, tags: ["model:status"])

    # clear the concurrent job key so that the next set of jobs can be scheduled in the delete status orchestration job
    clear_concurrency_key_for_batch(concurrent_job_key)
  end
end
