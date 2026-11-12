# typed: true
# frozen_string_literal: true

require "safe_timer"
require "sorbet-runtime"

# A background job that fetches batches of items and processes as many possible
# within a given time limit.  This job was copied from
# https://github.com/github/github/blob/master/app/jobs/timed_job.rb
class TimedJob < ApplicationJob
  extend T::Helpers
  extend T::Sig
  abstract!

  # Fetch a batch of items for processing.
  sig do
    abstract.
      params(args: T.untyped, offset_id: Integer, kwargs: T.untyped).
      returns(T.all(T::Enumerable[T.untyped], Object))
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
  sig { overridable.params(args: T.untyped, kwargs: T.untyped).returns(Float) }
  def timeout_sec(*args, **kwargs)
    kwargs.fetch(:timeout_sec, nil) || 1.minute.to_f
  end

  # rubocop:disable Style/ArgumentsForwarding
  sig { params(args: T.untyped, kwargs: T.untyped).void }
  def enqueue_next_job(*args, **kwargs)
    T.unsafe(self).class.perform_later(*args, **kwargs)
  end
  # rubocop:enable Style/ArgumentsForwarding

  sig { returns(String) }
  def initial_sequence_id
    @initial_sequence_id ||= SecureRandom.uuid
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
  def perform( # rubocop:disable Metrics/MethodLength
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
                            sequence_num_processed_items:,
                          })
    is_last_job = T.let(true, T::Boolean)
    num_processed_items = 0

    timeout = T.unsafe(self).timeout_sec(*args, **kwargs)
    SafeTimer.timeout(timeout) do |timer|
      loop do
        batch = T.unsafe(self).fetch_batch(*args, **kwargs)
        break if batch.blank?

        batch.each do |item|
          T.unsafe(self).process_item(*args, **kwargs, item: item)
          kwargs[:offset_id] = T.unsafe(self).item_id(*args, item: item, **kwargs)
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
      T.unsafe(self).enqueue_next_job(*args, **kwargs, num_in_sequence: num_in_sequence + 1)
    end
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def log_context
    kwargs = arguments[0] || {}
    initial_start = kwargs.fetch(:initial_start, Time.current.utc)
    offset_id = kwargs.fetch(:offset_id, 0)
    num_in_sequence = kwargs.fetch(:num_in_sequence, 1)
    sequence_id = kwargs.fetch(:sequence_id, initial_sequence_id)

    super.merge(
      "messaging.timed_job.initial_start" => initial_start,
      "messaging.timed_job.offset_id" => offset_id,
      "messaging.timed_job.max_timeout_sec" => timeout_sec(**kwargs),
      "messaging.timed_job.num_in_sequence" => num_in_sequence,
      "messaging.timed_job.sequence_id" => sequence_id,
    )
  end
end
