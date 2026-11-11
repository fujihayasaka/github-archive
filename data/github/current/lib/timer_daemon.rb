# typed: true
# frozen_string_literal: true

require "time"
require "gc_stat_logger"

# TimerDaemon - Cluster aware timer server
#
# The TimerDaemon is similar to cron but guarantees that each invocation
# of a task runs on only one of many TimerDaemon server processes. Its main
# goal is to provide multi-machine redundancy for scheduling tasks.
#
# TimerDaemon supports only a simple interval style of scheduling tasks. You
# specify the interval in seconds and provide a block that runs each time that
# interval elapses. Running the following in multiple TimerDaemon processes
# causes the message to be written only every 30s, possibly with a different
# processes winning each time.
#
#     TimerDaemon.schedule('something', 30) { puts "this runs every 30s" }
#
# Synchronization
# ---------------
#
# Redis is used to synchronize timerd processes across machines. Redis v2.1.0
# or greater is required. Earlier versions do not support the WATCH command
# used to ensure there are no race conditions in lock operations.
#
# When a TimerDaemon process detects that a task is eligible to be run, it
# attempts to obtain a lock in a central redis server. If the lock is already
# held, some other TimerDaemon won and the task is not invoked. If the lock is
# obtained, re-verify that the task is still eligible, invoke the task,
# and update the last run timestamp.
#
# TimerDaemon runs in a single thread. Task invocation blocks other tasks from
# being executed. For this reason, long-running jobs are typically not executed
# as part of a task block. Combine TimerDaemon with a work queue to manage work
# pools.
#
# Interval Overlap
# ----------------
#
# TimerDaemon runs tasks on time regardless of whether a previous run of
# that task is in progress. For instance, when a 10s interval takes 15s
# to complete you'll end up with a set of timer runs that look like this:
#
# 0s          10s           20s
# |----------------->
#             |------------------->
#                           |----------------->
#
# Care must be taken to avoid this situation (e.g., by keep long running
# tasks out of timerd) or all timerd processes will become backlogged and not be
# able to process jobs.
#
# Error Handling
# --------------
#
# TimerDaemon guarantees only that tasks will be started every interval. When an
# exception occurs in a task, no attempt will be made to run it again until the
# next interval.
#
# You can register a block to be called when an exception occurs in a task:
#
#     TimerDaemon.error { |boom, timer| warn "#{boom.class}: #{boom}" }
#
# Exceptions in tasks do not stop the TimerDaemon loop.
class TimerDaemon
  # This error gets raised if an interval smaller than 1 is used in a schedule
  class IntervalTooSmallError < ArgumentError; end

  # The redis client used to synchronize timerd processes.
  attr_accessor :redis
  private :redis

  # Write info-level logs to this IO stream.
  attr_accessor :info_logger

  # Deprecated: Use info_logger instead. Kept for backward compatibility.
  alias_method :err, :info_logger
  alias_method :err=, :info_logger=

  # Write error logs to this IO stream.
  attr_accessor :error_logger

  # Set true to cause the timer loop to break out
  attr_accessor :exit

  # The collection of configured timers.
  attr_reader :timers

  GCStats = ::GCStatLogger.new(stat_prefix: "timerd", sample_rate: 1)

  # Create a new TimerDaemon to manage a list of timers.
  def initialize(redis = nil, info_logger = nil, error_logger = nil)
    @timers = []
    @errors = []
    @redis = redis
    @info_logger = info_logger
    @error_logger = error_logger
    @exit = false
  end

  # Schedule a timer to run at regular intervals.
  #
  # name     - A string name for the timer. Must be unique.
  # interval - Number of seconds between task invocations.
  # options  - Hash of optional settings.
  #            :scope - Ensure only one instance per interval in the
  #                     given context (:global | :host | :process).
  #                     (default :global)
  # &block   - Block called when interval elapses.
  #
  # Returns nothing.
  def schedule(name, interval, options = {}, &block)
    raise IntervalTooSmallError if interval.to_i < 1

    scope = options[:scope] || :global
    klass = {
      host: HostTimer,
      process: ProcessTimer,
    }[scope] || GlobalTimer

    log("scheduling", {
      "gh.timerd.timer.class" => klass.name,
      "gh.timerd.timer.name" => name,
      "gh.timerd.timer.interval_seconds" => interval,
    })
    @timers << klass.new(name, interval, redis, &block)
  end

  # Force all timers to run, regardless of eligibility. Used to validate that
  # all scheduled blocks are runnable.
  #
  # Returns nothing.
  def validate
    @timers.each { |timer| timer.run!(force: true) }
  end

  # Register an error handler.
  #
  # When an exception occurs during the execution of a scheduled tasks,
  # registered handlers are called in sequence with the exception and timer
  # objects.
  #
  # &block - Block called when an exception occurs.
  #
  # Example
  #
  #   daemon.error do |boom, timer|
  #     Failbot.report(boom, :timer => timer.name)
  #   end
  #
  # Returns nothing.
  def error(&block)
    @errors << block
  end

  # Start the timer loop.
  #
  # duration - Optional number of seconds after which the loop should be exited.
  #
  # Returns never, unless the #shutdown method is called, in which case the
  # method will return after the current timer completes.
  def run!(duration = nil)
    log("arranging-timers")
    order!
    log("entering-timer-loop")
    started = Time.now
    while duration.nil? || (Time.now - started) <= duration.to_f
      check
      order!
      sleep_loop || break
    end
  end

  # Go to sleep until the next eligible timer is ready to run.
  #
  # Returns false when shutdown was detected, true otherwise.
  def sleep_loop
    next_run = @timers[0].next_run
    loop do
      if @exit
        log("leaving-timer-loop")
        return
      end
      delay = next_run - Time.now.to_f
      break if delay <= 0
      delay = 1.0 if delay > 1.0
      sleep delay
    end
    true
  end

  # Shutdown the timer loop. This causes the loop to exit on next iteration.
  # Typically called from signal traps.
  def shutdown
    @exit = true
  end

  def log_stream
    @info_logger || STDERR.method(:puts)
  end

  def error_log_stream
    @error_logger || log_stream
  end

  def log_context
    {
      "code.namespace" => self.class.name,
    }
  end

  def log(body, tags = {}, &blk)
    log_stream.call(body, log_context.merge(tags), &blk)
  end

  def log_error(body, tags = {}, &blk)
    error_log_stream.call(body, log_context.merge(tags), &blk)
  end

  # Run all eligible timers. Because timers are sorted by nearest to next
  # run time we can bail out as soon as we see a timer that is not eligible.
  def check
    @timers.each do |timer|
      return timer if !timer.eligible?
      begin
        timer.run { log("run", { "gh.timerd.timer.name" => timer.name }) }
      rescue => boom
        @errors.each { |b| b.call(boom, timer) }
        log_error("exception", { exception: boom })
        if boom.is_a?(Errno::ECONNREFUSED) || boom.is_a?(Redis::BaseError)
          sleep 5
        end
      end
    end
  end

  # Reorder timers in ascending order, placing the least recently ran timer at
  # the head of the list.
  def order!
    @timers.sort! { |t1, t2| t1.next_run <=> t2.next_run }
  end

  # An individual interval timer. Ensures only one instance will
  # fire globally every interval seconds.
  class GlobalTimer
    # The timer's name as defined in the timer config file.
    attr_reader :name

    # The timer's interval in integer seconds.
    attr_reader :interval

    # Exponential backoff parameters for lock retry. On each consecutive
    # contention failure the delay doubles up to the cap, with a small
    # random jitter (±percentage) to spread retries across processes.
    # This prevents tight-loop Redis storms when a lock is held or stranded.
    LOCK_RETRY_BASE_INTERVAL    = 5
    LOCK_RETRY_MAX_INTERVAL     = 60
    LOCK_RETRY_JITTER_FRACTION  = 0.25

    # Create a new timer object.
    def initialize(name, interval, redis, &block)
      @name = name
      @interval = interval.to_i
      @redis = redis
      @block = block
      @timestamp = nil
      @lock_backoff_until = nil
      @lock_retry_attempt = 0
    end

    # The Redis key used to store this timer's last-run timestamp.
    def timestamp_key
      "timer:#{name}"
    end

    # The Redis key used as a distributed lock for this timer.
    def lock_key
      "#{timestamp_key}:lock"
    end

    # The last run timestamp last obtained from redis. This value is read from
    # redis only via the explicit #refresh_timestamp method and is not
    # guaranteed to match what's in redis currently. You can always assume that
    # the timestamp is greater than or equal to this value however.
    def timestamp
      @timestamp || refresh_timestamp
    end

    # Reload the last run timestamp from redis. When the timestamp has
    # advanced it means another process completed the timer, so clear any
    # lock-contention backoff for this interval.
    def refresh_timestamp
      new_ts = @redis.get(timestamp_key).to_f
      if @timestamp && new_ts > @timestamp
        @lock_backoff_until = nil
        @lock_retry_attempt = 0
      end
      @timestamp = new_ts
    end

    # Is this timer eligible to be run based on the last run timestamp.
    def eligible?
      Time.now.to_i >= next_run
    end

    # The unix timestamp when this timer will next be eligible for run.
    def next_run
      base = (timestamp + interval).to_i
      return base unless @lock_backoff_until
      [base, @lock_backoff_until.ceil].max
    end

    # Run this timer's block but only if it's eligible. This refreshes the
    # timestamp from redis before performing the eligibility check.
    #
    # Returns true if the timer was run, nil otherwise.
    def run(&block)
      return if !eligible?
      refresh_timestamp
      run!(&block) if eligible?
    end

    # Run this timer's block after obtaining the lock in redis and reverifying
    # the last run timestamp.
    #
    # Returns true if the timer was run, nil when the lock could not be obtained
    # or the timer was found to be ineligible after obtaining the lock.
    def run!(force: false)
      lock do
        refresh_timestamp
        return if !eligible? && !force

        @timestamp = Time.now.to_f
        yield @timestamp if block_given?
        @redis.set(timestamp_key, @timestamp)
        TimerDaemon::GCStats.track_ruby_gc(tags: ["timer:#{name}"]) { @block.call(@timestamp) }
        return true
      end
      nil
    end

    # Obtain a lock for the timer and yield to the block. This method guarantees
    # that no two lock blocks will be in progress at the same time while the
    # timer's duration is within its interval.
    def lock
      start = Time.now.to_f
      if @redis.set(lock_key, start, ex: interval, nx: true)
        @lock_backoff_until = nil
        @lock_retry_attempt = 0
        begin
          yield
        ensure
          @redis.del(lock_key) if Time.now.to_f - start <= interval
        end
      else
        # somebody else has the lock. make sure its not stale.
        stale_lock_check lock_key
        @lock_backoff_until = calculate_lock_backoff
        @lock_retry_attempt += 1
      end
    end

    # Compute the next backoff deadline using exponential delay with ±jitter.
    # The base delay doubles each attempt (capped at LOCK_RETRY_MAX_INTERVAL)
    # and a random fraction is added to spread retries across processes.
    def calculate_lock_backoff
      max_delay = [LOCK_RETRY_MAX_INTERVAL, LOCK_RETRY_BASE_INTERVAL * (2**@lock_retry_attempt)].min
      jitter = max_delay * LOCK_RETRY_JITTER_FRACTION
      Time.now.to_f + max_delay + rand(-jitter..jitter)
    end

    # Safety net for cleaning up stale lock keys. Although the lock is now
    # acquired atomically with a TTL (SET EX NX), edge cases like Redis
    # failover or restore could leave orphaned keys. Use the atomic
    # watch / multi approach to clean up old lock keys that have expired.
    # This ensures that no race conditions exist when cleaning up a stale lock.
    #
    # See the redis documentation on Transactions for more detail:
    #
    # http://redis.io/topics/transactions
    #
    # Returns nothing.
    def stale_lock_check(lock_key)
      @redis.watch lock_key
      if ts = @redis.get(lock_key)
        if Time.now.to_f > ts.to_f + interval
          @redis.multi { |transaction| transaction.del(lock_key) }
        end
      end
    ensure
      @redis.unwatch
    end
  end

  # Ensures only one instance per host every interval.
  class HostTimer < GlobalTimer
    Hostname = Socket.gethostname

    def timestamp_key
      "timer:#{name}:#{Hostname}"
    end
  end

  # Runs one instance per process every interval.
  class ProcessTimer < HostTimer
    def timestamp_key
      "timer:#{name}:#{Hostname}:#{$$}"
    end
  end

  # Singleton interface.
  def self.instance
    @instance ||= TimerDaemon.new
  end

  def self.method_missing(name, *args, &block)
    if instance.respond_to?(name)
      instance.send(name, *args, &block)
    else
      super
    end
  end
end
