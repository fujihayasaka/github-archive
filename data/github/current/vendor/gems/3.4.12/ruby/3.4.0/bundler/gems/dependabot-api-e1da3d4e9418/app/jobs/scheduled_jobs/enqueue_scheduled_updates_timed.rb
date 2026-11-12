# typed: true
# frozen_string_literal: true

module ScheduledJobs
  class EnqueueScheduledUpdatesTimed < TimedJob
    extend T::Helpers

    queue_as :scheduled_updates
    default_retries_for_idempotent_jobs

    # Fetch a batch of update configs for processing.
    sig do
      override.
        params(args: T.untyped, offset_id: Integer, kwargs: T.untyped).
        returns(T.all(T::Enumerable[T.untyped], Object))
    end
    def fetch_batch(*args, offset_id:, **kwargs)
      next_id = T.let(offset_id + 1, Integer)

      batch_size = kwargs.fetch(:batch_size, 1000)
      configs = T.let([], T::Array[UpdateConfig])

      # TODO: Optimize the DB table so that the below lookup can be done in a single query.
      # Currently, selecting ids then filtering to only active configs can result in returning
      # an empty batch when there are more active configs to process.  When an empty batch is
      # returned the job will assume that there is nothing more to be processed and end the sequence.
      loop do
        ids = UpdateConfig.
              joins(:repo).
              where(update_schedule: schedule_type(**kwargs), id: next_id.., repos: { paused_at: nil }).
              order(id: :asc).
              limit(batch_size).
              pluck(:id)

        # stop iterating if there are no more ids left to process
        break if ids.empty?

        # The active scope is expensive to apply to a broad query so we apply it to each
        # batch instead.
        configs = UpdateConfig.active.where(id: ids).order(id: :asc).to_a

        # stop iterating when at least one config is found to be processed
        break if configs.present?

        # No active configs were found for the current batch of ids.  Update
        # next_id to the last id in the batch plus one and iterate to pull
        # another batch.
        next_id = ids.last + 1
      end

      configs
    end

    # Process a single update config.
    sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
    def process_item(*args, item:, **kwargs)
      job_started_at = kwargs.fetch(:initial_start, Time.current.utc)
      interval = EnqueueScheduledUpdates::IntervalVerification.new(update_config: item,
                                                                   started_at: job_started_at)
      return unless MetricsClient.time("enqueue_scheduled_updates_job.interval_verification.time") do
        interval.matches_config?
      end

      enqueue_scheduled_update_id = kwargs.fetch(:sequence_id, SecureRandom.uuid)
      CreateScheduledUpdateJob.
        set(**update_job_wait_args(item)).
        perform_later(update_config_id: item.id, enqueue_scheduled_update_id: enqueue_scheduled_update_id)

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
      MetricsClient.gauge("enqueue_scheduled_updates_job.processed", total_processed,
                          tags: { schedule: schedule_type(**kwargs) })

      # enqueued_count is strictly increasing across all jobs in the sequence
      MetricsClient.gauge("enqueue_scheduled_updates_job.enqueued", enqueued_count,
                          tags: { schedule: schedule_type(**kwargs) })
    end

    # Logic to be run after the final job in the sequence.
    sig { override.params(args: T.untyped, kwargs: T.untyped).void }
    def finalize_sequence(*args, **kwargs)
      # track the total E2E time taken for the sequence
      total_time = Time.current.utc - kwargs.fetch(:initial_start, Time.current.utc)
      MetricsClient.distribution("enqueue_scheduled_updates_job.dist.time", (total_time * 1000).round,
                                 tags: { schedule: schedule_type(**kwargs) })
    end

    # rubocop:disable Style/ArgumentsForwarding
    sig { params(args: T.untyped, kwargs: T.untyped).void }
    def enqueue_next_job(*args, **kwargs)
      # carry forward the enqueued_count across jobs in the sequence
      super(*T.unsafe(args), **kwargs, enqueued_count:)
    end
    # rubocop:enable Style/ArgumentsForwarding

    def perform(*args, **kwargs)
      @enqueued_count = kwargs.fetch(:enqueued_count, 0)
      job_schedule_type = schedule_type(**kwargs)
      unless EnqueueScheduledUpdates::VALID_SCHEDULES.include?(job_schedule_type)
        raise ArgumentError, "Invalid schedule: '#{job_schedule_type}'"
      end

      super
    rescue StandardError => e
      Dependabot::Logger.error(msg: "Failed enqueuing update jobs", error: e.message)
      raise
    end

    # Add schedule_type to all logging calls within the job
    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def log_context
      kwargs = arguments[0] || {}
      super.merge(schedule_type: schedule_type(**kwargs))
    end

    private

    sig { params(kwargs: T.untyped).returns(String) }
    def schedule_type(**kwargs)
      kwargs.fetch(:schedule_type, EnqueueScheduledUpdates::WEEKLY)
    end

    sig { returns(Integer) }
    attr_accessor :enqueued_count

    sig { params(update_config: UpdateConfig).returns(T::Hash[Symbol, T.untyped]) }
    def update_job_wait_args(update_config)
      if update_config.repo&.config_feature_enabled?(:spread_out_updates)
        { wait: rand(59).minutes + rand(59).seconds }
      elsif update_config.repo&.config_feature_enabled?(:spread_out_updates_time_of_day)
        time = Time.zone.now
        unless update_config.update_schedule_time_of_day.nil?
          time = time.change(
            min: update_config.update_schedule_time_of_day.min,
            sec: rand(59).seconds
          )
        end
        { wait_until: time }
      else
        {}
      end
    end
  end
end
