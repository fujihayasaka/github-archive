# typed: true
# frozen_string_literal: true

# This is a base class for a job that runs in batches
# and reschedules itself to process each batch in sequence.
# The default batch size is 100 records. This is a copy of BatchedJob that works with ActorId names instead
# of ids. This is because the ActorId is not a sequential number and we cannot use the id > ? clause.
#
# The algo runs like this:
# 1. Get a batch of n == BATCH_SIZE items
# 2. Process the batch
# 3. Record stats
# 4. Check if more items are available
# 5. If more available, schedule the job again to process the next batch
#
# To create a simple batched job you need to override just 2 methods:
# - process_batch(records, *args, **options)
# - next_batch(*args, **options)
# - next_batch_offset_item_name(batch, *args, **options)
# - batch_size(batch)

class ActorBatchedJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt
  queue_as :sync_feature_flags
  retry_on_dirty_exit

  #default size of a single batch to be processed
  BATCH_SIZE = 100

  # query for the batch to be processed.
  # you need to override this method in your custom job
  #
  # :timestamp - a timestamp for when the job was initially scheduled.
  #              Useful for querying using `created_at` attribute of records.
  # :offset_item_id - an id of the record to be used as the first one for the current batch in `where id > ?` clause.
  # **options - will contain all params you have passed to YourJob.perform_later(*args, options) call
  #
  # Both parameters will be injected into **options by the base algorithm
  # Additionally, you can use all params you have passed to YourJob.perform_later(*args, options) call
  #
  # Should return a batch object (e.g. array or records) that would be used by other methods
  def next_batch(*args, timestamp: Time.now.utc, offset_item_name: "", progress: 0, **options)
    raise NotImplementedError
  end

  # the logic of a single batch processing goes here.
  # you need to override this method in your custom job.
  #
  # batch - a batch object returned from next_batch()
  #
  # *args and **options will contain all params you have passed to YourJob.perform_later(*args, options) call
  def process_batch(batch, *args, **options)
    raise NotImplementedError
  end

  # for logic to be done after processing a batch and before the next job is enqueued
  # override this method to add additional logic, i.e. emitting telemetry or clearing job locks
  def finalize_batch(batch, *args, progress:, **options)
  end

  # checks whether there is another batch available for processing.
  # override if you need a more complex logic
  #
  # batch - a batch object returned from next_batch()
  #
  # **options will contain all params you have passed to YourJob.perform_later(*args, options) call
  def has_next_batch?(batch, **options)
    batch.size >= BATCH_SIZE
  end

  # gets the name of the item, which will be the first one in the next batch
  # override if you need a more specific logic
  #
  # batch - a batch object returned from next_batch()
  #
  # *arsg and **options will contain all params you have passed to YourJob.perform_later(*args, options) call
  def next_batch_offset_item_name(batch, *args, **options)
    raise NotImplementedError
  end

  # gets the size of the batch
  def batch_size(batch)
    raise NotImplementedError
  end

  # this method will be called after every run of the job is complete. It runs within an `ensure` block
  # override it if you need a custom cleanup for your job
  #
  # **options will contain all params you have passed to YourJob.perform_later(x, options) call
  def ensure_perform(finished_successfully:, **options)
  end

  private

  def perform(*args, initial_start: Time.now.utc, offset_item_name: "", progress: 0, **options)
    T.bind(self, T.untyped)

    # merge default params into options to propagate the values to all methods
    options = T.unsafe({ initial_start: initial_start, offset_item_name: offset_item_name }.merge(options))

    # save timestamp of the current job start
    this_job_started_at = Time.now.utc

    # A flag determining whether we have successfully processed all batches.
    finished_successfully = T.let(true, T::Boolean)

    GitHub.dogstats.distribution_timing_since("batched_job.time_enqueued.dist", initially_enqueued_at, tags: all_stats_tags)

    batch = GitHub.dogstats.distribution_time("batched_job.next_batch.dist", tags: all_stats_tags) do
      next_batch(*args, **options, timestamp: initially_enqueued_at)
    end
    record_batch_size(batch)

    GitHub.dogstats.distribution_time("batched_job.process_batch.dist", tags: all_stats_tags) do
      process_batch(batch, *args, **options)
    end

    GitHub.dogstats.distribution_time("batched_job.finalize_batch.dist", tags: all_stats_tags) do
      finalize_batch(batch, *args, **options, progress: progress + batch_size(batch))
    end
    return unless has_next_batch?(batch, **options)

    # There are more batches available, so mark as unfinished.
    finished_successfully = T.let(false, T::Boolean)
    last_name = next_batch_offset_item_name(batch, *args, **options)

    # schedule a continuation job
    self.class.perform_later(*args, **options, offset_item_name: last_name, progress: progress + batch_size(batch), initial_start: initial_start)
  rescue StandardError => error # rubocop:disable Lint/GenericRescue
    finished_successfully = false
    Failbot.report(error)
    raise error
  ensure
    record_single_run(this_job_started_at)
    record_total_duration(initial_start) if finished_successfully
    ensure_perform(**options, finished_successfully: finished_successfully)
  end

  def record_single_run(start_time)
    GitHub.dogstats.distribution_timing_since("batched_job.time.dist", start_time, tags: all_stats_tags)
  end

  def record_total_duration(start_time)
    GitHub.dogstats.distribution_timing_since("batched_job.total_time.dist", start_time, tags: all_stats_tags)
  end

  def record_batch_size(records)
    GitHub.dogstats.count("batched_job.batch_size", batch_size(records), tags: all_stats_tags)
  end
end
