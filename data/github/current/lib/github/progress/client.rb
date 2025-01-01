# typed: true
# frozen_string_literal: true

module GitHub
  module Progress
    class Client
      # Enough time for 5 exponentially longer retries by Active Job logic.
      DEFAULT_STALL_DURATION = 20.minutes
      MIN_STALL_DURATION = 1.second
      MAX_STALL_DURATION = 30.days

      EVENT_HYDRO_SCHEMA = "github.progress.v0.ProgressEvent"
      DATADOG_PREFIX = "github.progress.client"

      include GitHub::DatadogHelper

      attr_reader :key

      # Provide a string key that uniquely identifies the set of tasks for
      # which you will track progress.
      def initialize(key)
        validate_key!(key)
        @key = key
      end

      # Configure progress tracking for this set of tasks. The given stall
      # duration determines how much inactive time is allowed before progress
      # for this set of tasks is automatically stopped and deleted.
      def start(stall_duration: DEFAULT_STALL_DURATION)
        validate_stall_duration!(stall_duration)
        datadog_increment(:start)
        datadog_distribution(stall_duration: stall_duration.to_i)
        sync_publish_event_to_hydro(key: key, action: :start, config: { stall_duration: stall_duration.to_i })
      end

      # Increase the count of tasks to be done.
      def increment_denominator(by: 1)
        validate_positive_integer!(by)
        datadog_distribution(increment_denominator: by)
        sync_publish_event_to_hydro(key: key, action: :increment_denominator, value: by)
      end

      # Specify that no more tasks to be done will be identified.
      def lock_denominator
        datadog_increment(:lock_denominator)
        async_publish_event_to_hydro(key: key, action: :lock_denominator)
      end

      # If your use case doesn't require multiple increment_denominator calls
      # followed by a lock_denominator call, you can set and lock the
      # denominator in a single call if you know the exact number of tasks to
      # be done.
      def set_and_lock_denominator(denominator)
        validate_non_negative_integer!(denominator)
        datadog_distribution(set_and_lock_denominator: denominator)
        async_publish_event_to_hydro(key: key, action: :set_and_lock_denominator, value: denominator)
      end

      # Increase the count of tasks already done. If incrementing the numerator
      # results in progress becoming complete, this condition will
      # automatically be detected and proper instrumentation will be emitted.
      def increment_numerator(by: 1)
        validate_positive_integer!(by)
        datadog_distribution(increment_numerator: by)

        async_publish_event_to_hydro(key:, action: :increment_numerator, value: by, skip_partition_key: true)
      end

      # If your use case doesn't require multiple increment_numerator calls,
      # you can set the numerator and manually stop progress in a single call.
      # Note that progress will be permanently stopped regardless of whether
      # all tasks have been completed. Additional calls from this client will
      # be ignored.
      def set_numerator_and_stop(numerator)
        validate_non_negative_integer!(numerator)
        datadog_distribution(set_numerator_and_stop: numerator)
        async_publish_event_to_hydro(key: key, action: :set_numerator_and_stop, value: numerator)
      end

      # Manually stop and delete progress. Final instrumentation will be
      # emitted. Note that progress will be permanently stopped regardless of
      # whether all tasks have been completed. Additional calls from this
      # client will be ignored.
      def stop
        datadog_increment(:stop)
        async_publish_event_to_hydro(key: key, action: :stop)
      end

      # Used by the regularly scheduled StopAllStalledProgressJob to detect and
      # stop any progress that has stalled. This is not meant to be called by
      # your client instances but it is safe to do so. If progress hasn't
      # stalled, this will neither write to Redis nor emit instrumentation.
      def stop_if_stalled
        datadog_increment(:stop_if_stalled)
        async_publish_event_to_hydro(key: key, action: :stop_if_stalled)
      end

      private

      def validate_key!(key)
        unless key.instance_of?(String)
          raise ArgumentError, "The key must be a string. Given: #{key.class.name}"
        end

        if key.blank?
          raise ArgumentError, "The key must be present and uniquely identify a set of tasks."
        end
      end

      def validate_stall_duration!(stall_duration)
        unless stall_duration.is_a?(Integer)
          raise ArgumentError, <<~MSG
            The stall_duration must be provided in integer seconds.
            Valid: 3600
            Given: #{stall_duration.inspect}
            MSG
        end

        if stall_duration < MIN_STALL_DURATION
          raise ArgumentError, <<~MSG
            The stall_duration must be longer than #{MIN_STALL_DURATION.inspect}.
            Valid: #{1.hour.inspect}
            Given: #{stall_duration.seconds.inspect}
            MSG
        end

        if stall_duration > MAX_STALL_DURATION
          raise ArgumentError, <<~MSG
            The stall_duration must be shorter than #{MAX_STALL_DURATION.inspect}.
            Valid: #{1.hour.inspect}
            Given: #{stall_duration.seconds.inspect}
            MSG
        end
      end

      def validate_positive_integer!(value)
        unless value.is_a?(Integer) && value > 0
          raise ArgumentError, <<~MSG
            The value provided must be an integer greater than zero.
            Valid: 100
            Given: #{value.inspect}
            MSG
        end
      end

      def validate_non_negative_integer!(value)
        unless value.is_a?(Integer) && value >= 0
          raise ArgumentError, <<~MSG
            The value provided must be an integer greater than or equal to zero.
            Valid: 100
            Given: #{value.inspect}
            MSG
        end
      end

      # It's important that some actions are published synchronously.
      # Messages published through this synchrnonous publisher are guaranteed
      # to land in the Hydro backend in the same order they were published.
      #
      # The START and INCREMENT_DENOMINATOR actions are especially important
      # to process in order. Any action processed before START for a given key
      # is ignored. And any INCREMENT_DENOMINATOR call processed after
      # LOCK_DENOMINATOR is ignored. If START and INCREMENT_DENOMINATOR are
      # synchronous, we can be sure that START, INCREMENT_DENOMINATOR, and
      # LOCK_DENOMINATOR are processed in that sequence.
      def sync_publish_event_to_hydro(message)
        GitHub.sync_hydro_publisher.publish(message, schema: EVENT_HYDRO_SCHEMA, partition_key: key)
      end

      # This asynchronous publisher batches messages before flushing them to
      # the Hydro backend. This is more performant so it's preferred for
      # actions where processing order isn't important.
      #
      # The LOCK_DENOMINATOR action can be processed out of order because it's
      # only important that the LOCK_DENOMINATOR action is processed after the
      # denominator is set via every INCREMENT_DENOMINATOR action, which all
      # use the synchronous publisher, guaranteeing they land in the Hydro
      # backend before LOCK_DENOMINATOR.
      #
      # The SET_AND_LOCK_DENOMINATOR action can be processed out of order so
      # long as it is processed after the START action. The START action uses
      # the synchronous publisher, guaranteeing it lands in the Hydro backend
      # before SET_AND_LOCK_DENOMINATOR.
      #
      # The INCREMENT_DENOMINATOR action can also be processed out of order so
      # long as it they are processed after the START action.
      #
      # The three remaining actions are all force progress to stop. Those
      # actions are: SET_NUMERATOR_AND_STOP, STOP, and STOP_IF_STALLED. Because
      # these actions stop progress regardless of when they are processed, it's
      # acceptable for them to be processed out of order. In fact, it may even
      # be preferable for there to be some delay in publication of what's meant
      # to be the final action.
      def async_publish_event_to_hydro(skip_partition_key: false, **message)
        kwargs = skip_partition_key && github_progress_skip_partition_key_enabled? ? {} : { partition_key: key }
        GitHub.hydro_publisher.publish(message, schema: EVENT_HYDRO_SCHEMA, **kwargs)
      end

      def github_progress_skip_partition_key_enabled?
        GitHub::flipper[:github_progress_skip_partition_key].enabled?
      end
    end
  end
end
