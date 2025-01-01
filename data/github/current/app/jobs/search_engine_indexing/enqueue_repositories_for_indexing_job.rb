# typed: true
# frozen_string_literal: true

module SearchEngineIndexing
  class EnqueueRepositoriesForIndexingJob < BatchedJob
    INDEXING_DELAY = 5.minutes.freeze
    SCHEDULE_INTERVAL = 1.hour.freeze
    JOB_EXECUTION_BUFFER = 5.minutes.freeze

    BATCH_SIZE = 500.freeze

    retry_on_dirty_exit

    queue_as :search_engine_indexing

    around_perform :throttle_and_use_slow_reading_replica

    discard_on(StandardError) do |_job, error|
      Failbot.report(error)
    end

    def perform(...)
      return unless GitHub.flipper[:enqueue_repositories_for_bing_indexing_job].enabled?

      super
    end

    def process_batch(repository_batch, *_args, **_options)
      return if repository_batch.empty?

      urls = repository_batch.map(&:permalink)

      SubmitUrlsToBingJob.perform_later(urls)
    end

    # Returns an Array of Repository objects
    def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      timestamp_lower_bound = timestamp - INDEXING_DELAY - SCHEDULE_INTERVAL - JOB_EXECUTION_BUFFER
      timestamp_upper_bound = timestamp - INDEXING_DELAY

      with_read do
        Repository
          .select(:id, :name, :owner_login)
          .where(created_at: timestamp_lower_bound..timestamp_upper_bound)
          .public_scope
          .where("id > ?", offset_item_id)
          .order(id: :asc)
          .limit(BATCH_SIZE)
      end
    end

    private

    def throttle_and_use_slow_reading_replica
      Repository.throttle_with_retry do
        ActiveRecord::Base.connected_to(role: :reading_slow) do
          yield
        end
      end
    end
  end
end
