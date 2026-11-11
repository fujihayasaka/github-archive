# typed: false
# frozen_string_literal: true

module ScheduledJobs
  class DeleteOldUpdateJobsData < TimedJob
    extend T::Helpers
    include ActiveJob::ScheduledJob::Base

    DATA_RETENTION_PERIOD = 6.months.freeze
    JOB_LOCK_KEY = "delete_old_update_jobs_data"
    CONCURRENT_JOB_COUNT = 1
    REENQUEUE_DELAY = 2.seconds.freeze

    queue_as :db_cleanup
    schedule interval: 1.day

    # When reenqueueing this job after it has run for timeout_sec,
    # wait for 2 seconds so that the current job has a chance to
    # release the job lock before the next job tries to acquire it.
    self.reenqueue_options = { wait: REENQUEUE_DELAY }.freeze

    default_retries_for_idempotent_jobs
    # Ignore if unable to acquire lock, that means another job is running.
    discard_on Restraint::UnableToLock
    # Retry Freno errors after a delay
    retry_on Freno::Throttler::Error, wait: 20.seconds, attempts: (20.minutes / 20.seconds)

    # This is a low priority job that could potentially run for a very long time.
    # Set a shorter job timeout so the job sequence more frequently yields to other jobs.
    sig { override.params(args: T.untyped, kwargs: T.untyped).returns(Float) }
    def timeout_sec(*args, **kwargs)
      kwargs.fetch(:timeout_sec, nil) || 20.seconds.to_f
    end

    # rubocop:disable Metrics/AbcSize
    # Fetch batches of stale completed update job ids to delete.  This method will return an array of either:
    # 1. Arrays of ids to delete, when there are records to delete in offset_id..(offset_id + fetch_page_size)
    # 2. The range of searched ids, when there are no records to delete in offset_id..(offset_id + fetch_page_size).
    sig do
      override.
        params(args: T.untyped, offset_id: Integer, kwargs: T.untyped).
        returns(T.all(T::Enumerable[T.untyped], Object))
    end
    def fetch_batch(*args, offset_id:, **kwargs)
      read_batch_size = kwargs.fetch(:read_batch_size, 1000)
      write_batch_size = kwargs.fetch(:write_batch_size, 10)
      fetch_page_size = kwargs.fetch(:fetch_page_size, 1_000_000)

      start_id = offset_id + 1
      # Stop iteration when the job has reached the end of the table.
      return [] if start_id > max_update_jobs_table_id

      end_id = [start_id + fetch_page_size - 1, max_update_jobs_table_id].min
      range = (start_id..end_id)

      MetricsClient.distribution_time("scheduled_jobs.delete_old_update_jobs_data.fetch_batch.time") do
        ActiveRecord::Base.connected_to(role: :reading) do
          # Find the next batch of ids to delete after the given offset_id.
          job_ids = update_jobs_to_delete.where(id: range).order(id: :asc).limit(read_batch_size).pluck(:id)
          # If there are no deletable records found in the range, check whether to continue iteration or not
          if job_ids.empty?
            # If the first record in the id range was created inside of the retention period,
            # then we can stop iteration because all subsequent records will also be newer.
            created_at = UpdateJob.where(id: range).order(id: :asc).pick(:created_at)
            return [] if created_at.present? && created_at >= DATA_RETENTION_PERIOD.ago

            # return the full range so that the offset_id can be fast forwarded to the end of the range.
            return [range]
          end

          # Filter out any update job ids that have associated pull requests, since those jobs cannot be deleted.
          filtered_job_ids = job_ids - PullRequest.where(update_job_id: job_ids).distinct.pluck(:update_job_id)
          # Return the job_ids range when all found jobs have associated pull requests, so that
          # the offset_id can be fast forwarded to the end of the filtered job ids.
          return [(job_ids.first..job_ids.last)] if filtered_job_ids.empty?

          # Return an array of batches of update job ids to delete, where
          # each batch is an array of ids with length up to `write_batch_size`.
          # e.g. [[1,2,3], [4,5,6], ...]
          filtered_job_ids.each_slice(write_batch_size).to_a
        end
      end
    end
    # rubocop:enable Metrics/AbcSize

    sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).returns(Integer) }
    def item_id(*args, item:, **kwargs)
      # item is either:
      # 1. an array of update job ids representing one batch of update job ids
      #    returned by `fetch_batch`, in ascending order
      # 2. a range of update job ids that had no deletable records
      # In either case, to get the max id, return the last value.
      item.last.tap do |offset_id|
        MetricsClient.gauge("scheduled_jobs.delete_old_update_jobs_data.item_id", offset_id)
      end
    end

    # Process a batch of update job IDs to delete.
    sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
    def process_item(*args, item:, **kwargs)
      # item is either:
      # 1. an array of update job ids to delete found in `fetch_batch`
      # 2. a range that had no deletable records, which can be ignored
      return unless item.is_a?(Array)

      # We can call `delete_all_with_dependents` on the relation to delete all update jobs
      # in the batch, along with their dependent: :destroy associated records.
      deleted_records = Dependabot.freno_throttler.throttle(Freno::DEPENDABOT_CLUSTER) do
        MetricsClient.distribution_time("scheduled_jobs.delete_old_update_jobs_data.delete.time") do
          UpdateJob.transaction do
            UpdateJob.where(id: item).delete_all_with_dependents
          end
        end
      end

      MetricsClient.count("scheduled_jobs.delete_old_update_jobs_data.deleted", deleted_records)
      Dependabot::Logger.info(msg: "Deleted old update jobs", ids: item)
    end

    def perform(*args, **kwargs)
      return unless Dependabot.dotcom?

      Dependabot::Logger.info(msg: "Starting job", **log_context)

      Restraint.lock!(JOB_LOCK_KEY, CONCURRENT_JOB_COUNT, 1.minute) do
        super
      end

      if Restraint.locked?(JOB_LOCK_KEY, CONCURRENT_JOB_COUNT)
        Dependabot::Logger.warn(
          msg: "Lock still held unexpectedly after job completion.",
          **log_context
        )
      else
        Dependabot::Logger.info(
          msg: "Lock released after job completion.",
          **log_context
        )
      end
    end

    private

    sig { returns(ActiveRecord::Relation) }
    def update_jobs_to_delete
      UpdateJob.completed.where(updated_at: ...DATA_RETENTION_PERIOD.ago)
    end

    sig { returns(Integer) }
    def max_update_jobs_table_id
      return @max_update_jobs_table_id if defined?(@max_update_jobs_table_id)

      @max_update_jobs_table_id = UpdateJob.maximum(:id) || 0
    end
  end
end
