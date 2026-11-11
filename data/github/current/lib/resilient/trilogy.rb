# typed: true
# frozen_string_literal: true

require "resilient/circuit_breaker"
require "trilogy"
require "delegate"

module Resilient
  # A decorator for the Trilogy client to integrate Resilient::CircuitBreakers.
  class Trilogy < SimpleDelegator
    include Kernel

    # Base error class for errors. Inherit from Trilogy::BaseError so any rescues of
    # that in the code base that already exist will "just work".
    Error = Class.new(::Trilogy::BaseError)
    CircuitOpenError = Class.new(Error)

    # These errors indicate a database availability issue
    # It's unlikely that this will ever be an exhaustive list, but we should
    # make an effort to add status codes here if we see indicating availability
    # events.
    # Codes here should indicate transient errors related to database health, rather
    # than, for example, an error in the query being run.
    #
    # See https://dev.mysql.com/doc/mysql-errors/8.0/en/server-error-reference.html for the full list of MySQL server errors.
    # See https://dev.mysql.com/doc/mysql-errors/8.0/en/client-error-reference.html for the full list of MySQL client errors.
    # See https://dev.mysql.com/doc/refman/8.0/en/error-message-elements.html for more details on errors in MySQL.
    DB_AVAILABILITY_STATUS_CODES = [
      # MySQL server error codes
      1044, # ER_DBACCESS_DENIED_ERROR
      1045, # ER_ACCESS_DENIED_ERROR
      1053, # ER_SERVER_SHUTDOWN
      1135, # ER_CANT_CREATE_THREAD
      1203, # ER_TOO_MANY_USER_CONNECTIONS
      1290, # ER_OPTION_PREVENTS_STATEMENT

      # MySQL client error codes
      # These error codes likely originate from Vitess or ProxySQL as we do not use libmysql direclty.
      2006, # CR_SERVER_GONE_ERROR
      2013, # CR_SERVER_LOST
      2055, # CR_SERVER_LOST_EXTENDED
    ].freeze

    # A custom exception matcher that matches any exception that is a failure for the circuit breaker.
    FailureExceptionMatcher = Module.new do
      def self.===(exception)
        case exception
        when ::Trilogy::TimeoutError, ::Trilogy::BaseConnectionError, ::Trilogy::SSLError, ::SystemCallError
          true
        when ::Trilogy::Error
          DB_AVAILABILITY_STATUS_CODES.include?(exception.error_code)
        else
          false
        end
      end
    end

    # A custom exception matcher that matches any exception that is a success for the circuit breaker.
    SuccessExceptionMatcher = Module.new do
      def self.===(exception)
        case exception
        when ::Trilogy::CastError
          # We failed to cast the columns in the result set in the Trilogy client, however, the database responded successfully
          true
        else
          false
        end
      end
    end

    # Allowlist of queries that are not protected.
    QueryAllowlist = Regexp.union(
      /\A\s*ROLLBACK/i,
      /\A\s*COMMIT/i,
      /\A\s*RELEASE\s+SAVEPOINT/i,
    )

    # Result codes for the circuit breaker protected operations.
    RESULT_FAILURE, RESULT_SKIP, RESULT_SUCCESS = :failure, :skip, :success

    # Public: The Hash passed to Trilogy.new.
    attr_reader :trilogy_options

    # Public: The Hash passed to Resilient::CircuitBreaker::Properties.
    attr_reader :resilient_properties

    # Internal: The circuit breaker protecting network calls.
    attr_reader :circuit_breaker

    # Public: Initializes a new Resilient::Trilogy wrapper and the Trilogy instance
    # it wraps.
    #
    # trilogy_options - The Hash (symbol keys) of options to pass to Trilogy.new.
    # resilient_properties - The Hash (symbol keys) of options to pass to the
    #                     Resilient::CircuitBreaker::Properties.
    def initialize(trilogy_options:, resilient_properties:)
      @trilogy_options = trilogy_options
      @resilient_properties = resilient_properties

      name = @resilient_properties.fetch(:name) do
        raise ArgumentError, "resilient_properties requires name"
      end

      @circuit_breaker = Resilient::CircuitBreaker.get(name, @resilient_properties)
      @allow_next_attempt = false

      # ignore success on connect since we only want to count actual queries as successful.
      protect(ignore_success: true) { super(::Trilogy.new(@trilogy_options)) }
    end

    def query(*args)
      if query_allowlisted?(args.first)
        super
      else
        protect { super }
      end
    end

    def change_db(...)
      protect { super }
    end

    def ping
      # ignore success and failure on ping since this does not necessarily tell us the health of the database.
      protect(ignore_success: true, ignore_failure: true) { super }
    end

    private

    # Returns true if the query is allowed to skip the circuit breaker's protection.
    def query_allowlisted?(sql)
      QueryAllowlist =~ sql
    rescue ArgumentError
      raise if sql.valid_encoding?

      # If the sql contains invalid data for the encoding, the query *is not* AllowListed.
      false
    end

    # Protects the object being delegated to with a circuit breaker.
    # Allows ignoring the count of success or failure towards the circuit breaker metrics.
    #
    # Note: Certain exceptions (e.g., ::GitHub::DatabaseQueryDisabler::DatabaseDisabledError) tell us nothing about
    # the health of the database and should not be counted towards the circuit breaker metrics.
    # If an exception occurs that is not explictly mapped to success or failure for the circuit breaker,
    # the circuit breaker metrics will not be updated for that exception.
    def protect(ignore_success: false, ignore_failure: false)
      result = RESULT_SKIP

      raise CircuitOpenError unless @circuit_breaker.allow_request? || @allow_next_attempt

      OpenTelemetry::Instrumentation::Trilogy.with_attributes(circuit_breaker_attributes) do
        yield.tap { result = RESULT_SUCCESS }
      end
    rescue SuccessExceptionMatcher => e
      result = RESULT_SUCCESS
      log_exceptions(result, e)
      raise
    rescue FailureExceptionMatcher => e
      result = RESULT_FAILURE
      log_exceptions(result, e)
      raise
    rescue => e
      log_exceptions(result, e)
      raise
    ensure
      @allow_next_attempt = false

      if result == RESULT_SUCCESS
        if ignore_success
          @allow_next_attempt = true
        else
          @circuit_breaker.success
        end
      elsif result == RESULT_FAILURE && !ignore_failure
        @circuit_breaker.failure
      end
    end

    def circuit_breaker_attributes
      attributes = {
        "circuit_breaker.key" => @circuit_breaker.key.name,
        "circuit_breaker.error_threshold_percentage" => @circuit_breaker.properties.error_threshold_percentage,
        "circuit_breaker.current_error_percentage" => @circuit_breaker.metrics.error_percentage,
        "circuit_breaker.request_volume_threshold" => @circuit_breaker.properties.request_volume_threshold,
        "circuit_breaker.total_requests" => @circuit_breaker.metrics.requests,
        "circuit_breaker.window_size" => @circuit_breaker.properties.window_size_in_seconds,
        "circuit_breaker.bucket_size" => @circuit_breaker.properties.bucket_size_in_seconds,
        "circuit_breaker.force_open" => @circuit_breaker.properties.force_open,
        "circuit_breaker.force_closed" => @circuit_breaker.properties.force_closed,
        "circuit_breaker.open" => @circuit_breaker.open,
      }

      attributes
    end

    def log_exceptions(result, exception)
      log_fields = {
        :exception => exception,
        "gh.trilogy.circuit_breaker.key" => @circuit_breaker.key.name,
        "gh.trilogy.circuit_breaker.result" => result
      }

      if exception.respond_to?(:error_code) && exception.error_code
        log_fields["gh.trilogy.error_code"] = exception.error_code
      end

      GitHub.logger.warn("encountered a trilogy error", log_fields)
    end
  end
end
