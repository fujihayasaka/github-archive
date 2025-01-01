# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module SearchEngineIndexing
  class EnqueueUsersForIndexingJob < BatchedJob
    INDEXING_DELAY = 7.days.freeze
    SCHEDULE_INTERVAL = 1.day.freeze
    JOB_EXECUTION_BUFFER = 1.hour.freeze

    BATCH_SIZE = 500.freeze

    retry_on_dirty_exit

    queue_as :search_engine_indexing

    around_perform :throttle_and_use_slow_reading_replica

    discard_on(StandardError) do |_job, error|
      Failbot.report(error)
    end

    def perform(...)
      return unless GitHub.flipper[:enqueue_users_for_bing_indexing_job].enabled?

      super
    end

    def process_batch(batch, *_args, **_options)
      return if batch.empty?

      urls = batch.map { |_id, login| "#{GitHub.url}/#{login}" }

      SubmitUrlsToBingJob.perform_later(urls)
    end

    # Returns an Array of [id, login] pairs.
    def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      timestamp_lower_bound = timestamp - INDEXING_DELAY - SCHEDULE_INTERVAL - JOB_EXECUTION_BUFFER
      timestamp_upper_bound = timestamp - INDEXING_DELAY

      with_read do
        User
          .from("users IGNORE INDEX FOR ORDER BY(PRIMARY)")
          .not_spammy
          .not_suspended
          .where(created_at: timestamp_lower_bound..timestamp_upper_bound)
          .where("id > ?", offset_item_id)
          .order(created_at: :asc, id: :asc)
          .limit(BATCH_SIZE)
          .pluck(:id, :login)
      end
    end

    def next_batch_offset_item_id(batch, *_args, **_options)
      batch.last[0]
    end

    private

    def throttle_and_use_slow_reading_replica
      User.throttle_with_retry do
        ActiveRecord::Base.connected_to(role: :reading_slow) do
          yield
        end
      end
    end
  end
end
