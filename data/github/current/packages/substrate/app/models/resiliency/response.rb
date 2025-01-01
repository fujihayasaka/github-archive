# typed: true
# frozen_string_literal: true

require "forwardable"

module Resiliency
  class Response < SimpleDelegator
    class Executor
      def self.call(default_value, &block)
        success = false
        error = nil
        value = if block_given?
          begin
            result = GitHub::ResilienceMixin.tag_queries(QUERY_TAG) do
              yield
            end
            success = true
            if result.nil? && default_value
              default_value
            else
              result
            end
          rescue StandardError => boom
            helper = ResilienceHelper::GracefulDegradationErrorHandler.new(boom, allowed_errors: UnavailableExceptions, excluded_errors: [])

            raise unless helper.degradable?

            GitHub.dogstats.increment(DATADOG_METRIC, tags: ["error_class:#{boom.class.name}", "catalog_service:#{GitHub.context[:catalog_service]}"])
            helper.send_metrics("Resiliency::Response", nil)

            error = boom
            default_value
          end
        else
          success = true
          default_value
        end

        { success:, error:, value: }
      end
    end

    # Use this base error class to automatically rescue errors inside Resiliency::Response
    class UnavailableError < StandardError
    end

    # Internal: All exceptions that mean a service could be unavailable due to
    # timeouts, network errors or mysql failures.
    UnavailableExceptions = T.let([
      ActiveRecord::ConnectionNotEstablished, # don't believe we'll ever hit this
      ActiveRecord::StatementInvalid,
      SystemCallError, # Errno::ECONNREFUSED, Errno::ECONNRESET and friends
      GitHub::DatabaseQueryDisabler::DatabaseDisabledError,
      Resiliency::Response::UnavailableError,
      GitHub::KV::UnavailableError,
      # Redis
      Redis::CommandError, # locking jobs have a depency on Redis
      Redis::ConnectionError,
      Redis::CannotConnectError,
      Redis::TimeoutError,
      IO::EAGAINWaitReadable, # occurs during Redis timeouts
      # SpokesAPI
      SpokesAPI::ResourceExhausted, # occurs when the spokes api is rate limited
      SpokesAPI::TimedOut,
    ], T::Array[T.class_of(StandardError)])

    DATADOG_METRIC = "resiliency.unavailable_exception.count"
    QUERY_TAG = "fallback:Resiliency::Response"

    attr_reader :value
    attr_reader :error

    def initialize(default_value = nil, &block)
      @success = false
      @error = nil

      result = Executor.call(default_value, &block)

      @success = result[:success]
      @error = result[:error]
      @value = result[:value]

      super(@value)
    end

    def value!
      __getobj__.send(:raise, @error) unless @success
      @value
    end

    def success?
      @success
    end

    def failed?
      !success?
    end
  end
end
