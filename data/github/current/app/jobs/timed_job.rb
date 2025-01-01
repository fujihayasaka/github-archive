# typed: true
# frozen_string_literal: true

# A background job that fetches batches of items and processes as many possible
# within a given time limit.
class TimedJob < ApplicationJob
  extend T::Helpers
  include GitHub::Memoizer
  abstract!

  # Fetch a batch of items for processing.
  sig do
    abstract
      .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
      .returns(T.all(T::Enumerable[T.untyped], Object))
  end
  def fetch_batch(*args, offset_id:, **kwargs); end

  # Process a single item.
  sig { abstract.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
  def process_item(*args, item:, **kwargs); end

  # Return the primary ID for an item.
  # This method is used to determine the new `offset_id`.
  sig { overridable.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).returns(Integer) }
  def item_id(*args, item:, **kwargs)
    item.id
  end

  # Logic to be run at the end of each job,
  # before finalizing the sequence or enqueuing the next job.
  # Example: emit telemetry of how many items were processed.
  sig { overridable.params(args: T.untyped, is_last_job: T::Boolean, num_processed_items: Integer, kwargs: T.untyped).void }
  def post_process(*args, is_last_job:, num_processed_items:, **kwargs); end

  # Logic to be run after the final job in the sequence.
  sig { overridable.params(args: T.untyped, kwargs: T.untyped).void }
  def finalize_sequence(*args, **kwargs); end

  # The maximum runtime of each job in seconds.
  #
  # Do not set this higher than 5 minutes since "kube… imposes a 5 minute max
  # execution time constraint to cap pod shutdown time"
  # (https://gh.io/background-jobs-best-practices-limit-execution-time).
  sig { overridable.returns(Float) }
  def timeout_sec
    1.minute.to_f
  end

  sig { params(args: T.untyped, kwargs: T.untyped).void }
  def enqueue_next_job(*args, **kwargs)
    clear_lock
    T.unsafe(self).class.perform_later(*args, **kwargs)
  end

  sig { returns(String) }
  memoize def initial_sequence_id
    SecureRandom.uuid
  end

  # Currently, there's a bug in Tapioca that cannot properly parse `args: T.untyped`.
  # Thus, this sig is commented out until that bug is fixed.
  #
  # sig do
  #   params(
  #     args: T.untyped,
  #     initial_start: Time,
  #     offset_id: Integer,
  #     num_in_sequence: Integer,
  #     sequence_id: String, # A unique ID to tie together the sequence of jobs.
  #     sequence_num_processed_items: Integer, # The total number of items processed in the sequence so far.
  #     kwargs: T.untyped
  #   ).void
  # end
  def perform(
    *args,
    initial_start: Time.current.utc,
    offset_id: 0,
    num_in_sequence: 1,
    sequence_id: initial_sequence_id,
    sequence_num_processed_items: 0,
    **kwargs
  )
    kwargs = kwargs.merge({
      initial_start:,
      offset_id:,
      num_in_sequence:,
      sequence_id:,
      sequence_num_processed_items:
    })
    is_last_job = T.let(true, T::Boolean)
    num_processed_items = 0

    GitHub::SafeTimer.timeout(timeout_sec) do |timer|
      loop do
        batch = T.unsafe(self).fetch_batch(*args, **kwargs)
        break if batch.blank?

        batch.each do |item|
          T.unsafe(self).process_item(*args, **kwargs, item: item)
          kwargs[:offset_id] = item_id(item: item)
          num_processed_items += 1
          break is_last_job = false if timer.expired?
        end

        break is_last_job = false if timer.expired?
      end
    end

    kwargs[:sequence_num_processed_items] += num_processed_items

    T.unsafe(self).post_process(*args, **kwargs, is_last_job:, num_processed_items:)

    if is_last_job
      T.unsafe(self).finalize_sequence(*args, **kwargs)
    else
      T.unsafe(self).enqueue_next_job(*args, **kwargs.merge(num_in_sequence: num_in_sequence + 1))
    end
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def logging_context
    kwargs = arguments[0] || {}
    initial_start = kwargs.fetch(:initial_start, Time.current.utc)
    offset_id = kwargs.fetch(:offset_id, 0)
    num_in_sequence = kwargs.fetch(:num_in_sequence, 1)
    sequence_id = kwargs.fetch(:sequence_id, initial_sequence_id)

    super.merge({
      "gh.timed_job.initial_start" => initial_start,
      "gh.timed_job.offset_id" => offset_id,
      "gh.timed_job.max_timeout_sec" => timeout_sec,
      "gh.timed_job.num_in_sequence" => num_in_sequence,
      "gh.timed_job.sequence_id" => sequence_id
    })
  end
end
