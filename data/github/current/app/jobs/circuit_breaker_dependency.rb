# typed: true
# frozen_string_literal: true

require "resilient/circuit_breaker"

module CircuitBreakerDependency
  extend T::Helpers

  include Kernel

  # Key to use to for collecting circuit breaker statistics
  # If no key is defined, circuit breaking is disabled
  # String - Defaults to nil
  attr_accessor :circuit_breaker_key

  # Ability to pause processor without expire
  attr_writer :circuit_breaker_automatically_reset
  AUTOMATICALLY_RESET = true

  # Length of time to wait until the job is rescheduled
  SCHEDULE_INTERVAL_SECONDS = 300

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
  ERROR_THRESHOLD_PERCENTAGE = 10

  # Number of seconds in the statistical window
  attr_writer :circuit_breaker_window_size_in_seconds
  WINDOW_SIZE_IN_SECONDS = 30

  # Size of buckets in statistical window
  attr_writer :circuit_breaker_bucket_size_in_seconds
  BUCKET_SIZE_IN_SECONDS = 5

  # Instrumenter for circuit breaker metrics
  attr_writer :circuit_breaker_instrumenter
  INSTRUMENTER = GitHub.respond_to?(:instrument) ? GitHub : GlobalInstrumenter

  # Number of times to retry a job before failing
  RETRY_ATTEMPTS = 10

  # This is a hash of additional message parameters which will be injected into the log
  attr_accessor :circuit_breaker_additional_message_parameters

  # A lambda that will be called when the circuit breaker is successful
  attr_accessor :circuit_breaker_success_action

  class CircuitBreakerError < StandardError; end

  # Public: Get the circuit breaker instance.  `get` keeps a registry of circuits by key to prevent
  #         creating multiple instances of the same circuit breaker for a key.
  #
  # Returns a Resilient::CircuitBreaker
  def circuit_breaker
    key = circuit_breaker_key.present? ? circuit_breaker_key : self.class.name
    Resilient::CircuitBreaker.get(key, circuit_breaker_options)
  end

  # Public: Execute the job with circuit breaker protection.  If the circuit breaker is open, the fallback action will be executed.
  #
  # Returns nothing
  def execute_with_circuit_breaker(job_parameters, rescue_errors: nil, &block)
    starting_message(job_parameters)

    if circuit_breaker.allow_request?
      if rescue_errors&.any?
        begin
          # execute processing block and mark success or failure
          yield if block

          circuit_breaker.success

          circuit_breaker_success_action.call if circuit_breaker_success_action.present?
        rescue *rescue_errors => e
          circuit_breaker.failure
          # do fallback
          execute_fallback(job_parameters, e)
        end
      else
        begin
          # execute processing block and mark success or failure
          yield if block

          circuit_breaker.success

          circuit_breaker_success_action.call if circuit_breaker_success_action
        rescue => e
          circuit_breaker.failure
          # do fallback
          execute_fallback(job_parameters, e)
        end
      end
    else
      # do fallback
      execute_fallback(job_parameters)
    end
  end

  protected

  # Protected: Log starting message
  #
  # Returns nothing
  def starting_message(job_parameters)
    logger_options = message_parameters(job_parameters)
    logger_options["info.message"] = "Starting #{self.class.name}"
    GitHub.logger.info(logger_options)
  end

  # Protected: Log fallback message
  #
  # Returns nothing
  def fallback_message(job_parameters, error = nil)
    logger_options = message_parameters(job_parameters)

    if error
      logger_options["error.message"] = "Circuit Breaker failure for #{self.class.name}"
      GitHub.logger.error(logger_options)
    else
      logger_options["info.message"] = "Circuit Breaker open for #{self.class.name}"
      GitHub.logger.info(logger_options)
    end
  end

  private

  # Private: Generates message parameters from the job parameters, circuit breaker options and additional parameters
  #
  # Returns a Hash
  def message_parameters(job_parameters)
    logger_options = { "code.namespace" => self.class.name }
    job_parameters.each { |key, value| logger_options["job.parameter.#{key}"] = value }
    circuit_breaker_options.each { |key, value| logger_options["job.circuit_breaker.#{key}"] = value }
    circuit_breaker_additional_message_parameters.each { |key, value| logger_options[key] = value } if circuit_breaker_additional_message_parameters.present?
    logger_options
  end

  # Private: Execute fallback will execute the fallback action if the circuit breaker is open.
  #          By default it will schedule the job to run in the future.
  #
  # Returns nothing
  def execute_fallback(job_parameters, error = nil)
    fallback_message(job_parameters, error)

    raise CircuitBreakerError
  end

  # For more information about options see
  # https://github.com/jnunemaker/resilient#default-properties
  def option_keys
    [:force_open, :force_closed, :sleep_window_seconds, :request_volume_threshold,
      :error_threshold_percentage, :window_size_in_seconds, :bucket_size_in_seconds,
      :instrumenter]
  end

  # Private: Get the configured circuit breaker options
  #
  # Returns a Hash
  def circuit_breaker_options
    option_keys.each_with_object({}) do |key, options|
      options[key] = config(key)
    end
  end

  # Private: Get a single configuration value, or default
  #
  # Returns a configuration value
  def config(key)
    return nil unless key.present?
    iv_name = "@circuit_breaker_#{key}".to_sym
    const_name = key.to_s.upcase
    value = instance_variable_get(iv_name)
    value.nil? ? self.class.const_get(const_name) : value
  end
end
