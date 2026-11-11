# typed: false
# frozen_string_literal: true

module ScheduledJobs
  class EnqueueScheduledUpdateJobs < TimedJob
    extend T::Helpers
    include ActiveJob::ScheduledJob::Base

    # Enqueue CreateScheduledUpdateJob in batches to reduce the number of
    # roundtrips to the job queue service and speed up the overall processing time of the sequence.
    ENQUEUE_BATCH_SIZE = 100
    REENQUEUE_DELAY = 2.seconds.freeze

    queue_as :scheduled_updates
    default_retries_for_idempotent_jobs

    discard_on(Restraint::UnableToLock)

    schedule interval: 5.minutes
    # When reenqueueing this job after it has run for timeout_sec,
    # wait for 2 seconds so that the current job has a chance to
    # release the job lock before the next job tries to acquire it.
    self.reenqueue_options = { wait: REENQUEUE_DELAY }.freeze

    # Fetch a batch of update configs for processing.
    sig do
      override.
        params(args: T.untyped, offset_id: Integer, kwargs: T.untyped).
        returns(T.all(T::Enumerable[T.untyped], Object))
    end
    def fetch_batch(*args, offset_id:, **kwargs)
      read_batch_size = kwargs.fetch(:batch_size, 1000)

      UpdateConfig.
        where(next_enqueue_at: ..Time.current.utc).
        order(next_enqueue_at: :asc, id: :asc).
        limit(read_batch_size).
        each_slice(ENQUEUE_BATCH_SIZE).
        to_a
    end

    # This job doesn't use an offset_id when fetching batches since it always fetches
    # configs with the oldest `next_enqueue_at` value.
    # Returns 0 to indicate to readers this value that offset_id is unused.
    sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).returns(Integer) }
    def item_id(*args, item:, **kwargs)
      0
    end

    # Schedule jobs for UpdateConfigs.
    sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
    def process_item(*args, item:, **kwargs)
      enqueue_scheduled_update_id = kwargs.fetch(:sequence_id, SecureRandom.uuid)

      configs_jobs_map = item.index_with do |config|
        CreateScheduledUpdateJob.new(
          update_config_id: config.id, enqueue_scheduled_update_id: enqueue_scheduled_update_id
        )
      end
      ActiveJob.perform_all_later(configs_jobs_map.values)

      # Only update configs whose jobs were successfully enqueued to avoid updating next_enqueue_at
      # for configs that failed to enqueue.  These configs will be reprocessed by a later job run.
      item = item.select { |config| configs_jobs_map[config].successfully_enqueued? }

      item.each do |config|
        scheduling_lag = Time.current.utc - config.next_enqueue_at
        MetricsClient.distribution("enqueue_scheduled_updates_job.schedule_lag.time", (scheduling_lag * 1000).round)

        # Set next_enqueue_at after successfully scheduling the job to avoid
        # skipping scheduled updates if job enqueueing fails (e.g., yearly schedules)
        config.set_next_enqueue_at
      end

      # Save updated configs in a transaction to reduce DB roundtrips
      UpdateConfig.transaction { item.each(&:save!) }
      self.enqueued_count += item.size
    end

    # Logic to be run at the end of each job,
    # before finalizing the sequence or enqueuing the next job.
    # Example: emit telemetry of how many items were processed.
    sig { override.params(args: T.untyped, is_last_job: T::Boolean, num_processed_items: Integer, kwargs: T.untyped).void }
    def post_process(*args, is_last_job:, num_processed_items:, **kwargs)
      Dependabot::Logger.info(msg: "Enqueued update jobs", count: enqueued_count)
      MetricsClient.count("enqueue_scheduled_updates_job.enqueued.count", enqueued_count)
    end

    def perform(*args, **kwargs)
      # prevent multiple of these jobs running simultaneously
      Restraint.lock!("enqueue_scheduled_update_jobs", 1, 2.minutes) do
        @enqueued_count = 0

        super
      rescue StandardError => e
        Dependabot::Logger.error(msg: "Failed enqueuing update jobs", error: e.message)
        raise
      end
    end

    private

    sig { returns(Integer) }
    attr_accessor :enqueued_count
  end
end
