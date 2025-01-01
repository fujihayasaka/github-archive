# typed: true
# frozen_string_literal: true

module GitHub
  module Progress
    class Server
      REDIS_KEY_PREFIX = "github:progress"
      CURRENT_KEY = "#{REDIS_KEY_PREFIX}:current"
      STALL_DURATION_CONFIG_FIELD = "stall_duration"

      INSTRUMENTATION_EVENT_SUFFIX = "progress"
      UPDATE_HYDRO_SCHEMA = "github.progress.v0.ProgressUpdate"
      STOP_HYDRO_TOPIC = "github.progress.v0.ProgressStop"
      DATADOG_PREFIX = "github.progress.server"

      STARTED = :started
      COMPLETED = :completed
      STALLED = :stalled
      STOPPED = :stopped

      include GitHub::DatadogHelper

      def self.stop_all_stalled
        current_key_count, stalled_keys =
          redis.pipelined do
            redis.zcard(CURRENT_KEY)
            redis.zrangebyscore(CURRENT_KEY, 0, now_in_usec)
          end

        GitHub.dogstats.gauge("#{DATADOG_PREFIX}.current", current_key_count)
        GitHub.dogstats.distribution("#{DATADOG_PREFIX}.stalled", stalled_keys.count, tags: ["nonzero:#{stalled_keys.any?}"])

        stalled_keys.each do |stalled_key|
          Client.new(stalled_key).stop_if_stalled
        end

        stalled_keys.any?
      end

      def self.redis
        GitHub.job_coordination_redis
      end

      def self.now_in_usec
        now = Time.zone.now
        (now.to_i * 1_000_000) + now.usec
      end

      def self.time_from_usec(value)
        sec, usec = value.divmod(1_000_000)
        Time.zone.at(sec).change(usec: usec)
      end

      delegate :redis, :now_in_usec, :time_from_usec, to: :"self.class"

      attr_reader :key, :stopped_at

      def initialize(key)
        @key = key
      end

      def start(stall_duration:, **)
        datadog_increment(:start, tags: ["success:#{!current?}"])
        return false if current?

        datadog_distribution(stall_duration: stall_duration)

        # We can "pipeline" these commands for better performance because we
        # have confidence that each command will succeed and we don't need to
        # know the interstitial results of each command.
        redis.pipelined do
          # Attempt to add this progress to the sorted set of monitored progress
          # with a score representing the Unix timestamp in microseconds for when
          # progress is set to stall if no further activity is received. This
          # value will be increased as new activity is received.
          redis.zadd(
            CURRENT_KEY,
            [now_in_usec + (stall_duration * 1_000_000), key],
          )

          # Save configuration for this progress. Currently, only one field is
          # stored in configuration.
          redis.hset(config_key, STALL_DURATION_CONFIG_FIELD, stall_duration)

          # Make sure the denominator is unlocked.
          redis.del(denominator_locked_key)

          # Initialize keys used to track this progress.
          redis.mset(
            denominator_key, 0,
            numerator_key, 0,
            started_at_key, now_in_usec,
          )
        end

        reload
        instrument(:start)
        instrument(:update)
        true
      end

      def increment_denominator(by:)
        datadog_distribution(increment_denominator: by, tags: ["success:#{current? && denominator_unlocked?}"])
        return false unless current? && denominator_unlocked?

        redis.pipelined do
          redis.incrby(denominator_key, by)
          extend_stalls_at
        end

        reload
        instrument(:update)
        true
      end

      def lock_denominator
        datadog_increment(:lock_denominator, tags: ["success:#{current? && denominator_unlocked?}"])
        return false unless current? && denominator_unlocked?

        redis.pipelined do
          redis.set(denominator_locked_key, now_in_usec)
          extend_stalls_at
        end

        reload
        instrument(:update)
        instrument_stop_and_reset if completed?
        true
      end

      def set_and_lock_denominator(denominator)
        datadog_distribution(set_and_lock_denominator: denominator, tags: ["success:#{current? && denominator_unlocked?}"])
        return false unless current? && denominator_unlocked?

        redis.pipelined do
          redis.mset(denominator_key, denominator, denominator_locked_key, now_in_usec)
          extend_stalls_at
        end

        reload
        instrument(:update)
        instrument_stop_and_reset if completed?
        true
      end

      def increment_numerator(by:)
        datadog_distribution(increment_numerator: by, tags: ["success:#{current?}"])
        return false unless current?

        redis.pipelined do
          redis.incrby(numerator_key, by)
          extend_stalls_at
        end

        reload
        instrument(:update)
        instrument_stop_and_reset if completed?
        true
      end

      def set_numerator_and_stop(numerator)
        datadog_distribution(set_numerator_and_stop: numerator, tags: ["success:#{current?}"])
        return false unless current?

        redis.pipelined do
          redis.set(numerator_key, numerator)
          extend_stalls_at
        end

        reload
        instrument(:update)
        instrument_stop_and_reset
        true
      end

      def stop
        datadog_increment(:stop, tags: ["success:#{current?}"])
        return false unless current?

        instrument_stop_and_reset
        true
      end

      def stop_if_stalled
        datadog_increment(:stop_if_stalled, tags: ["success:#{stalled?}"])
        return false unless stalled?

        instrument_stop_and_reset
        true
      end

      # PUBLIC API above

      def empty?
        numerator.nil? &&
          denominator.nil? &&
          started_at.nil? &&
          stall_duration.nil? &&
          stalls_at.nil?
      end

      def current?
        numerator.present? &&
          denominator.present? &&
          started_at.present? &&
          stall_duration.present? &&
          stalls_at.present?
      end

      def numerator
        data.fetch(:numerator)
      end

      def denominator
        data.fetch(:denominator)
      end

      def denominator_locked?
        data.fetch(:denominator_locked)
      end

      def denominator_unlocked?
        !denominator_locked?
      end

      def started_at
        data.fetch(:started_at)
      end

      def updated_at
        data.fetch(:updated_at)
      end

      def stall_duration
        data.fetch(:stall_duration)
      end

      def stalls_at
        data.fetch(:stalls_at)
      end

      def data
        return @data if @data

        # Fetch all of the data for this progress in one Redis roundtrip.
        output =
          redis.pipelined do
            redis.zscore(CURRENT_KEY, key)
            redis.hget(config_key, STALL_DURATION_CONFIG_FIELD)
            redis.mget(numerator_key, denominator_key, denominator_locked_key, started_at_key)
          end

        stalls_at = output[0].presence && time_from_usec(output[0].to_i)
        stall_duration = output[1].presence&.to_i
        numerator = output[2][0].presence&.to_i
        denominator = output[2][1].presence&.to_i
        denominator_locked = output[2][2].present?
        started_at = output[2][3].presence && time_from_usec(output[2][3].to_i)
        updated_at = stalls_at && stall_duration && (stalls_at - stall_duration)

        @data = {
          numerator: numerator,
          denominator: denominator,
          denominator_locked: denominator_locked,
          started_at: started_at,
          updated_at: updated_at,
          stall_duration: stall_duration,
          stalls_at: stalls_at,
        }
      end

      def reload
        @data = nil
        @stopped_at = nil
      end

      def status
        case
        when denominator_locked? && (numerator >= denominator)
          COMPLETED
        when stalls_at&.past?
          STALLED
        when stopped_at
          STOPPED
        else
          STARTED
        end
      end

      def completed?
        status == COMPLETED
      end

      def stalled?
        status == STALLED
      end

      private

      def config_key
        "#{REDIS_KEY_PREFIX}:config:#{key}"
      end

      def numerator_key
        "#{REDIS_KEY_PREFIX}:numerator:#{key}"
      end

      def denominator_key
        "#{REDIS_KEY_PREFIX}:denominator:#{key}"
      end

      def denominator_locked_key
        "#{REDIS_KEY_PREFIX}:denominator_locked:#{key}"
      end

      def started_at_key
        "#{REDIS_KEY_PREFIX}:started_at:#{key}"
      end

      def extend_stalls_at
        redis.zadd(
          CURRENT_KEY,
          [now_in_usec + (stall_duration * 1_000_000), key],
          xx: true, # Don't add, only update an existing score
          gt: true, # Only update if the new score is greater
        )
      end

      def instrument_stop_and_reset
        @stopped_at = Time.zone.now
        instrument(:stop)
        reset
        reload
      end

      def reset
        redis.pipelined do
          redis.del(config_key, numerator_key, denominator_key, denominator_locked_key, started_at_key)
          redis.zrem(CURRENT_KEY, key)
        end
      end

      def instrument(event)
        datadog_increment(:update, tags: ["event:#{event}"])

        payload = payload(event: event)
        GitHub.instrument("#{event}.#{INSTRUMENTATION_EVENT_SUFFIX}", payload)
        GitHub.hydro_publisher.publish(payload, schema: UPDATE_HYDRO_SCHEMA, partition_key: key)

        # Publish an message identical to the STOP event payload above, but to
        # a separate topic for easier consumption by processors that are only
        # concerned with STOP events.
        if event == :stop
          GitHub.hydro_publisher.publish(payload, schema: UPDATE_HYDRO_SCHEMA, topic: STOP_HYDRO_TOPIC, partition_key: key)

          if started_at && stopped_at
            final_duration = GitHub::Dogstats.duration(started_at, stopped_at)
            datadog_distribution(final_duration: final_duration)
          end

          datadog_distribution(final_numerator: numerator) if numerator
          datadog_distribution(final_denominator: denominator) if denominator
        end
      end

      def payload(event:)
        {
          key: key,
          event: event,
          status: status,
          numerator: numerator,
          denominator: denominator,
          denominator_locked: denominator_locked?,
          started_at: started_at,
          updated_at: updated_at,
          stopped_at: stopped_at,
          config: {
            stall_duration: stall_duration,
          },
        }
      end

      def datadog_tags
        [
          "empty:#{empty?}",
          "current:#{current?}",
          "denominator_locked:#{denominator_locked?}",
          "status:#{status}",
        ]
      end
    end
  end
end
