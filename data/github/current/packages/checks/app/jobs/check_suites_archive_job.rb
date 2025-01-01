# typed: true
# frozen_string_literal: true

class CheckSuitesArchiveJob < ApplicationJob
  include GitHub::Tracing
  include ChecksJobUtility

  ARCHIVE_BATCH_SIZE = 25
  READ_BATCH_SIZE = 5000

  queue_as :archive_check_suites
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Archives a batch of check_suites between a start and end id (inclusive)
  def perform(updated_at_start:, updated_at_end:, concurrent_job_key:)
    raise ArgumentError, "updated_at_start must be provided." unless updated_at_start.present?
    raise ArgumentError, "updated_at_end must be provided." unless updated_at_end.present?
    raise ArgumentError, "concurrent_job_key must be provided." unless concurrent_job_key.present?

    lock! do
      archive_check_suites(updated_at_start: updated_at_start, updated_at_end: updated_at_end, concurrent_job_key: concurrent_job_key)
    rescue ActiveRecord::RecordNotFound, StandardError => e # rubocop:todo Lint/GenericRescue
      Failbot.report(e)
      raise e
    end
  end

  private

  # https://thehub.github.com/epd/engineering/products-and-services/dotcom/background-jobs/lockable-jobs/#restraint-locks
  def lock!
    restraint = GitHub::Restraint.new
    lock_key = self.class.name
    max_concurrent_jobs = 7  # Maximum of 7 concurrent jobs
    lock_ttl = 5.minutes
    restraint.lock!(T.must(lock_key), max_concurrent_jobs, lock_ttl) do
      yield
    end
  rescue GitHub::Restraint::UnableToLock
    # Skip job if we try to run while lock is held
    GitHub.dogstats.increment("checks.check_suites_archive_job.unable_to_lock")
  end

  def archive_check_suites(updated_at_start:, updated_at_end:, concurrent_job_key:)
    total_archived_count = 0

    loop do
      archivable_check_suites = CheckSuite
        .from("check_suites FORCE INDEX(index_check_suites_on_is_archived_updated_at)")
        .where("is_archived = false")
        .where("updated_at between :updated_at_start AND :updated_at_end", updated_at_start: updated_at_start, updated_at_end: updated_at_end)
        .where("updated_at <= :updated_at", updated_at: archive_threshold_days.ago)
        .order(id: :asc)
        .limit(READ_BATCH_SIZE)
        .pluck(:repository_id, :id)

      break if archivable_check_suites.empty?

      repo_id_pairs = group_by_repository_id(archivable_check_suites)

      repo_id_pairs.each do |repository_id, check_suite_ids|
        check_suite_ids.in_groups_of(ARCHIVE_BATCH_SIZE) do |batch|
          ActiveRecord::Base.connected_to(role: :writing) do
            archived_count = CheckSuite.throttle do
              CheckSuite
                .from("check_suites FORCE INDEX(PRIMARY)")
                .where(repository_id: repository_id, id: batch)
                .update_all(archived_at: DateTime.now, updated_at: DateTime.now) # Update updated_at so that later during deletion we can efficiently search for records to delete using the index_check_suites_on_is_archived_updated_at index
            end
            total_archived_count = total_archived_count + archived_count
          end
        end
      end
    end

    GitHub.dogstats.count("checks.archivable.archived", total_archived_count, tags: ["model:checksuite"])

    # clear the concurrent job key so that the next set of jobs can be scheduled in the check suite orchestration archive job
    concurrency_key_for_batch_exists?(concurrent_job_key)
  end
end
