# typed: false
# frozen_string_literal: true

module ScheduledJobs
  class DeleteOldPullRequestsData < TimedJob
    extend T::Helpers
    include ActiveJob::ScheduledJob::Base

    DATA_RETENTION_PERIOD = 2.years.freeze
    JOB_LOCK_KEY = "delete_old_pull_requests_data"
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

    # Fetch batches of stale closed pull request ids to delete.
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
      return [] if start_id > max_pull_request_table_id

      end_id = [start_id + fetch_page_size - 1, max_pull_request_table_id].min
      range = (start_id..end_id)

      MetricsClient.distribution_time("scheduled_jobs.delete_old_pull_requests_data.fetch_batch.time") do
        ActiveRecord::Base.connected_to(role: :reading) do
          # Find the next record to delete after the given offset_id.
          pr_ids = pull_requests_to_delete.where(id: range).order(id: :asc).limit(read_batch_size).pluck(:id)
          if pr_ids.empty?
            # If the first record in the id range was created inside of the retention period,
            # then we can stop iteration because all subsequent records will also be newer.
            created_at = PullRequest.where(id: range).order(id: :asc).pick(:created_at)
            return [] if created_at.present? && created_at >= DATA_RETENTION_PERIOD.ago

            # return the full range so that the offset_id can be fast forwarded to the end of the range.
            return [range]
          end

          # Return an array of arrays of pull request ids to delete, where
          # each array is a batch of ids with length up to `write_batch_size`.
          # e.g. [[1,2,3], [4,5,6], ...].
          pr_ids.each_slice(write_batch_size).to_a
        end
      end
    end

    sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).returns(Integer) }
    def item_id(*args, item:, **kwargs)
      # item is either:
      # 1. an array of pull request ids representing one batch of pull request ids
      #    returned by `fetch_batch`, in ascending order
      # 2. a range of pull request ids that had no deletable records
      # In either case, to get the max id, return the last value.
      item.last.tap do |offset_id|
        MetricsClient.gauge("scheduled_jobs.delete_old_pull_requests_data.item_id", offset_id)
      end
    end

    # Process a batch of pull request IDs to delete.
    sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
    def process_item(*args, item:, **kwargs)
      # item is either:
      # 1. an array of pull request ids to delete found in `fetch_batch`
      # 2. a range that had no deletable records, which can be ignored
      return unless item.is_a?(Array)

      # We can call `delete_all_with_dependents` on the relation to delete all pull requests
      # in the batch, along with their dependent: :destroy associated records.
      deleted_records = Dependabot.freno_throttler.throttle(Freno::DEPENDABOT_CLUSTER) do
        MetricsClient.distribution_time("scheduled_jobs.delete_old_pull_requests_data.delete.time") do
          PullRequest.transaction do
            PullRequest.where(id: item).delete_all_with_dependents
          end
        end
      end

      MetricsClient.count("scheduled_jobs.delete_old_pull_requests_data.deleted", deleted_records)
      Dependabot::Logger.info(msg: "Deleted old pull requests", ids: item)
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

    def pull_requests_to_delete
      PullRequest.not_open.where(updated_at: ...DATA_RETENTION_PERIOD.ago)
    end

    def max_pull_request_table_id
      return @max_pull_request_table_id if defined?(@max_pull_request_table_id)

      @max_pull_request_table_id = PullRequest.maximum(:id) || 0
    end
  end
end
