# typed: false
# frozen_string_literal: true

require "resilient/circuit_breaker"

module GitHub
  module StreamProcessors
    module CircuitBreaking
      # Key to use to for collecting circuit breaker statistics
      # If no key is defined, circuit breaking is disabled
      # String - Defaults to nil
      attr_accessor :circuit_breaker_key

      # Ability to pause processor without expire
      attr_writer :circuit_breaker_automatically_reset
      AUTOMATICALLY_RESET = true

      # Length of time to pause processor
      attr_writer :circuit_breaker_pause_duration_seconds
      PAUSE_DURATION_SECONDS = 600

      # Allows forcing the circuit open (stopping all requests)
      attr_writer :circuit_breaker_force_open
      FORCE_OPEN = false

      # Allows forcing the circuit closes (allowing all requests)
      # instrumentation will still happen allowing testing of configurations
      attr_writer :circuit_breaker_force_closed
      FORCE_CLOSED = false

      # Seconds after tripping circuit before allowing retry
      attr_writer :circuit_breaker_sleep_window_seconds
      SLEEP_WINDOW_SECONDS = 5

      # Number of requests that must be made within a statistical window
      # before open/close decisions are made using stats
      attr_writer :circuit_breaker_request_volume_threshold
      REQUEST_VOLUME_THRESHOLD = 5

      # % of "marks" that must be failed to trip the circuit
      attr_writer :circuit_breaker_error_threshold_percentage
      ERROR_THRESHOLD_PERCENTAGE = 50

      # Number of seconds in the statistical window
      attr_writer :circuit_breaker_window_size_in_seconds
      WINDOW_SIZE_IN_SECONDS = 30

      # Size of buckets in statistical window
      attr_writer :circuit_breaker_bucket_size_in_seconds
      BUCKET_SIZE_IN_SECONDS = 5

      # Instrumenter for circuit breaker metrics
      attr_writer :circuit_breaker_instrumenter
      INSTRUMENTER = GlobalInstrumenter

      def circuit_breaker
        return nil unless circuit_breaker_key.present?
        return @circuit_breaker if defined?(@circuit_breaker)
        @circuit_breaker = Resilient::CircuitBreaker.get(circuit_breaker_key, circuit_breaker_options)
      end

      def circuit_breaker_options
        option_keys.each_with_object({}) do |key, options|
          options[key] = config(key)
        end
      end

      def circuit_breaker_record_success
        circuit_breaker&.success
      end

      def circuit_breaker_record_failure
        circuit_breaker&.failure
      end

      def circuit_breaker_pause_processing?
        circuit_breaker.present? ? !circuit_breaker.allow_request? : false
      end

      def circuit_breaker_pause_duration
        automatically_reset = config(:automatically_reset)
        duration = config(:pause_duration_seconds)
        automatically_reset.present? ? duration.seconds.from_now : nil
      end

      private

      # For more information about options see
      # https://github.com/jnunemaker/resilient#default-properties
      def option_keys
        [:force_open, :force_closed, :sleep_window_seconds, :request_volume_threshold,
         :error_threshold_percentage, :window_size_in_seconds, :bucket_size_in_seconds,
         :instrumenter]
      end

      def config(key)
        return nil unless key.present?
        iv_name = "@circuit_breaker_#{key}".to_sym
        const_name = key.to_s.upcase
        value = instance_variable_get(iv_name)
        value.nil? ? self.class.const_get(const_name) : value
      end
    end
  end
end
