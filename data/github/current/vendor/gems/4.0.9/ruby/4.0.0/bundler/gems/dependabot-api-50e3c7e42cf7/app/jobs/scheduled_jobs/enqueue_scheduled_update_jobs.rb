# typed: false
# frozen_string_literal: true

module ScheduledJobs
  class EnqueueScheduledUpdateJobs < TimedJob
    extend T::Helpers
    include ActiveJob::ScheduledJob::Base

    queue_as :scheduled_updates
    default_retries_for_idempotent_jobs

    discard_on(Restraint::UnableToLock)

    schedule interval: 5.minutes

    # Fetch a batch of update configs for processing.
    sig do
      override.
        params(args: T.untyped, offset_id: Integer, kwargs: T.untyped).
        returns(T.all(T::Enumerable[T.untyped], Object))
    end
    def fetch_batch(*args, offset_id:, **kwargs)
      batch_size = kwargs.fetch(:batch_size, 1000)

      UpdateConfig.
        where(next_enqueue_at: ..Time.current.utc).
        order(next_enqueue_at: :asc, id: :asc).
        limit(batch_size)
    end

    # Process a single update config.
    sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
    def process_item(*args, item:, **kwargs)
      enqueue_scheduled_update_id = kwargs.fetch(:sequence_id, SecureRandom.uuid)

      CreateScheduledUpdateJob.
        perform_later(update_config_id: item.id, enqueue_scheduled_update_id: enqueue_scheduled_update_id)

      scheduling_lag = Time.current.utc - item.next_enqueue_at
      MetricsClient.distribution("enqueue_scheduled_updates_job.schedule_lag.time", (scheduling_lag * 1000).round)

      # Update next_enqueue_at after successfully scheduling the job to avoid
      # skipping scheduled updates if job enqueueing fails (e.g., yearly schedules)
      item.set_next_enqueue_at

      self.enqueued_count += 1
    end

    # Logic to be run at the end of each job,
    # before finalizing the sequence or enqueuing the next job.
    # Example: emit telemetry of how many items were processed.
    sig { override.params(args: T.untyped, is_last_job: T::Boolean, num_processed_items: Integer, kwargs: T.untyped).void }
    def post_process(*args, is_last_job:, num_processed_items:, **kwargs)
      Dependabot::Logger.info(msg: "Enqueued update jobs", count: enqueued_count)

      # sequence_num_processed_items is strictly increasing across all jobs in the sequence
      total_processed = kwargs.fetch(:sequence_num_processed_items, 0)
      MetricsClient.gauge("enqueue_scheduled_updates_job.processed", total_processed)

      # enqueued_count is strictly increasing across all jobs in the sequence
      MetricsClient.gauge("enqueue_scheduled_updates_job.enqueued", enqueued_count)
    end

    # Logic to be run after the final job in the sequence.
    sig { override.params(args: T.untyped, kwargs: T.untyped).void }
    def finalize_sequence(*args, **kwargs)
      # track the total E2E time taken for the sequence
      total_time = Time.current.utc - kwargs.fetch(:initial_start, Time.current.utc)
      MetricsClient.distribution("enqueue_scheduled_updates_job.dist.time", (total_time * 1000).round)
    end

    # rubocop:disable Style/ArgumentsForwarding
    sig { params(args: T.untyped, kwargs: T.untyped).void }
    def enqueue_next_job(*args, **kwargs)
      # carry forward the enqueued_count across jobs in the sequence
      super(*T.unsafe(args), **kwargs, enqueued_count:)
    end
    # rubocop:enable Style/ArgumentsForwarding

    def perform(*args, **kwargs)
      # prevent multiple of these jobs running simultaneously
      Restraint.new.lock!("enqueue_scheduled_update_jobs", 1, 2.minutes) do
        @enqueued_count = kwargs.fetch(:enqueued_count, 0)

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
