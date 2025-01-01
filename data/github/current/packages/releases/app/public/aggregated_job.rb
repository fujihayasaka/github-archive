# typed: strict
# frozen_string_literal: true

# AggregatedJob is a base class for jobs that need to aggregate values during a given interval.
# It provides methods to retrieve aggregated values from Redis.
# It also avoids enqueueing duplicate jobs (see enqueue_aggregated_per_interval).
# When a perform was successful, it cleans up Redis value.
#
# To create a simple aggregated job, you simply need to inherit from this class.
# And add two keyword arguments to your `def perform` method:
# - interval
# - interval_timestamp
#
# Optionally you also can override these methods:
# - unique_id - a string that uniquely identifies the job
#
# Check slotted_counter_increment_aggregated_job.rb and the corresponding test for usage example.
class AggregatedJob < ApplicationJob
  extend T::Sig

  sig { returns(T.nilable(Integer)) }
  attr_accessor :interval

  sig { returns(T.nilable(Integer)) }
  attr_accessor :interval_timestamp

  before_perform do |job|
    job.interval = job.arguments.last[:interval]
    job.interval_timestamp = job.arguments.last[:interval_timestamp]
  end

  # Always clean up Redis value after a successful perform.
  after_perform do
    GitHub.job_coordination_redis.del(counter_key)
  end

  # Retrieves aggregated value from Redis.
  sig { returns(T.nilable(String)) }
  def aggregated_value
    @aggregated_value ||= T.let(GitHub.job_coordination_redis.get(counter_key), T.nilable(String))
  end

  # Constructs a Redis key to store aggregated value.
  # The key includes class name, interval, and unique_id of the job.
  sig { returns(String) }
  def counter_key
    class_name = self.class.name&.underscore
    unique_id = self.class.unique_id(self.arguments)
    @counter_key ||= T.let("job:aggregated_per_interval:#{class_name}:#{interval}:#{interval_timestamp}:#{unique_id}", T.nilable(String))
  end

  # Constructs a Redis key to apply restraint lock against.
  # The key includes class name, interval, and unique_id of the job.
  #
  # Usage of restraint lock is optional, but higly recommended because AggregatedJob uses shared state.
  # This property should be used in `perform` method of your subclass.
  # Check slotted_counter_increment_aggregated_job.rb for usage example.
  sig { returns(String) }
  def restraint_lock_key
    class_name = self.class.name&.underscore
    unique_id = self.class.unique_id(self.arguments)
    @lock_key ||= T.let("job:restraint_lock:#{class_name}:#{interval}:#{interval_timestamp}:#{unique_id}", T.nilable(String))
  end

  # Constructs unique_id from job arguments.
  # Defaults to join all positional args with colon, and omitting keyword arguments.
  # Can be overridden in subclasses.
  sig { params(args: T.untyped).returns(String) }
  def self.unique_id(args)
    if args.last.kind_of?(Hash) && args.last[:interval] && args.last[:interval_timestamp]
      args[0...-1].join(":")
    else
      args.join(":")
    end
  end

  # Enqueue this job to be performed only _once_ at the end of the specified interval.
  # The job must inherit AggregatedJob, and define redis key and interval to be enqueued.
  # When performing the job will get the aggregated counter value of all the jobs enqueued.
  #
  # I.e. if you enqueue 100 jobs with the same `unique_id` at the same time,
  # only the first job will be ran at the end of the interval, and the `aggregated_value` will be 100.
  # Any additional jobs enqueued during the interval will be dropped.
  #
  # This is useful to throttle jobs that can be "spammed" by user actions.
  # If an user performs 100 asset downloads in 10 seconds,
  # and there is an expensive operation we want to perform "on download",
  # such as incrementing download counter in MySQL database,
  # using this helper method will ensure that the job only runs once,
  # and uses `aggregated_value` while performing the operation.
  #
  # The interval begins when the first unique job (identified by `unique_id`) is enqueued.
  # It ends after the number of seconds defined by `interval` passed,
  # but only after the job was successfully performed,
  # and the Redis value has been cleaned up in `after_perform` callback.
  #
  # @param args [Array] arguments to be passed to the job's perform method.
  # @param interval [Integer] Interval (in seconds) in which the job needs to aggregate values, and avoid enqueueing duplicate jobs. Defaults to 60 seconds.
  # @return [Boolean] true if the job was successfully enqueued, false otherwise.
  sig { params(args: T.untyped, interval: Integer).returns(T::Boolean) }
  def self.enqueue_aggregated_per_interval(args, interval: 60)
    # Avoid enqueueing an arbitrary job, as the job must define redis key, interval, and cleanup logic.
    raise ArgumentError, "In order to enqueue the job it must inherit AggregatedJob" unless self.superclass == AggregatedJob
    raise ArgumentError, "Interval for AggregatedJob can't be negative or zero" if interval <= 0

    class_name = T.must(self.name).underscore
    tags = ["class:#{class_name}", "interval:#{interval}"]
    interval_timestamp = Time.now.to_i / interval
    counter_key = "job:aggregated_per_interval:#{class_name}:#{interval}:#{interval_timestamp}:#{unique_id(args)}"

    # EX seconds -- Set the specified expire time, in seconds.
    # Normally the Redis value should be cleaned up by the job after successfull perform.
    # See aggregated_job.rb `after_perform`.
    # However, to avoid the risk when job failures could leave these counter keys forever,
    # we still want to set expiration to some knowingly big number (e.g. a day).
    ex = 24.hours.in_seconds

    # NX -- Only set the key if it does not already exist.
    nx = true

    # SET NX returns true when the key doesn't exist
    # In this case this is the first time we schedule the job with this unique_id
    # SET NX returns false when the key already exists
    # In this case we proceed to the `else` block and simply increment the key value
    if GitHub.job_coordination_redis.set(counter_key, 1, ex:, nx:)
      GitHub.dogstats.increment("job.aggregated_per_interval.queued", tags: tags)

      # Add additional threshold to give the system some time
      # to capture any writes before the job reads and persists the aggregated values
      threshold = 10.seconds

      set(wait: interval.seconds + threshold).perform_later(*args, interval:, interval_timestamp:)
      true
    else
      GitHub.job_coordination_redis.incr(counter_key)
      GitHub.dogstats.increment("job.aggregated_per_interval.duplicate", tags: tags)
      false
    end
  end
end
