# typed: true
# frozen_string_literal: true

module GitHub
  module ResilienceMixin
    extend T::Helpers

    QUERY_TAG = "fallback:ResilienceMixin"
    DATABASE_ERROR_TYPES_ALLOWLIST = [
      ActiveRecord::ActiveRecordError,
      GitHub::SQL::BadBind,
      SystemCallError,
      RequestDurationManager::TimeBudgetIsOverError,
      ::Redis::BaseConnectionError,
      GitHub::KV::UnavailableError,
    ]

    @@database_errors = []

    GRACEFUL_DEGRADATION_BUFFER_MS = 2000

    sig do
      type_parameters(:T)
        .params(
          query_tag: String,
          block: T.proc.returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def self.tag_queries(query_tag, &block)
      GitHub::MysqlInstrumenter.track_degradable_queries do
        GitHub::MysqlInstrumenter.tag_queries(query_tag, &block)
      end
    end

    private

    sig { returns(T::Array[Exception]) }
    def database_errors
      @@database_errors
    end

    def clear_database_errors
      @@database_errors.clear
    end

    sig do
      type_parameters(:T)
        .params(
          fallback: T.nilable(T.all(Object, T.any(
            T.proc.returns(T.type_parameter(:T)),
            T.type_parameter(:T),
          ))),
          allowed_error_types: T::Array[Class],
          excluded_error_types: T.nilable(T::Array[Class]),
          block: T.proc.returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
    end
    def with_database_error_fallback(fallback: nil, allowed_error_types: DATABASE_ERROR_TYPES_ALLOWLIST, excluded_error_types: nil, &block)
      with_graceful_degradation_buffer do
        GitHub::ResilienceMixin.tag_queries(GitHub::ResilienceMixin::QUERY_TAG) do
          yield # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end
      end
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      graceful_error_handler = ResilienceHelper::GracefulDegradationErrorHandler.new(e, allowed_errors: allowed_error_types, excluded_errors: excluded_error_types)

      Kernel.raise unless graceful_error_handler.degradable?

      graceful_error_handler.send_metrics("with_database_error_fallback", @current_template)
      @@database_errors << e
      fallback&.respond_to?(:call) ? T.unsafe(fallback).call : fallback
    end

    sig do
      type_parameters(:Result, :Fallback)
        .params(
          promise: Promise[T.type_parameter(:Result)],
          fallback: T.nilable(T.all(Object, T.any(
            T.proc.returns(T.type_parameter(:Fallback)),
            T.type_parameter(:Fallback),
          ))),
         allowed_error_types: T::Array[Class],
         excluded_error_types: T.nilable(T::Array[Class]),
        ).returns(
          Promise[T.any(
            T.type_parameter(:Result),
            T.type_parameter(:Fallback)
          )]
        )
    end
    def with_async_database_error_fallback(promise, fallback:, allowed_error_types: DATABASE_ERROR_TYPES_ALLOWLIST, excluded_error_types: nil)
      PromiseWrapper.new(
        promise,
        fallback: fallback,
        current_template: @current_template,
        allowed_error_types: allowed_error_types,
        excluded_error_types: excluded_error_types
      ).new_promise
    end

    # Executes the provided block of code preseving a time buffer to graceful degrade the request.
    #
    # In case the time budget is over, the block will not be executed and a
    # `GitHub::RequestDurationManager::TimeBudgetIsOverError` will be raised.
    # Otherwise, the block will be executed and the remaining time budget will be yielded as an argument.
    #
    # Note: In case this method runs in a Job context, or others that are not currently budgeted,
    # the remaining time budget will be `nil`.
    #
    #
    # @example
    #
    #   This method can be used combined with the MySQL MAX_EXECUTION_TIME optimizer hint
    #   to ensure that a query won't exhaust the entire web request time budget.
    #
    #   result = with_graceful_degradation_buffer do |remaining_time_budget_ms|
    #     Repository.where(organization:).limit_execution_time(limit_ms: remaining_time_budget_ms)
    #   end
    #
    #   Note: that the remaining_time_budget_ms is computed only once per block invocation. So, if you want to
    #   use it in multiple queries, you should wrap each query in a separate block.
    #
    # @param block [Proc] The block of code to execute.
    # @return [Object] The result of the block execution.
    # @raise [StandardError] Any errors that occur during the execution of the block are propagated.
    sig do
      type_parameters(:T)
        .params(block: T.proc.params(remaining_time_budget_ms: T.nilable(Integer)).returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def with_graceful_degradation_buffer(&block)
      GitHub::RequestDurationManager.raise_if_time_budget_is_over(time_buffer_ms: GRACEFUL_DEGRADATION_BUFFER_MS) do |remaining_time_budget_ms|
        yield(remaining_time_budget_ms)
      end
    end

    class PromiseWrapper
      QUERY_TAG = "fallback:ResilienceMixin::PromiseWrapper"

      attr_reader :new_promise, :fallback, :allowed_error_types, :excluded_error_types, :current_template

      def initialize(wrapped_promise, fallback:, current_template:, allowed_error_types: DATABASE_ERROR_TYPES_ALLOWLIST, excluded_error_types: nil)
        @wrapped_promise = wrapped_promise
        @new_promise = Promise.new
        @new_promise.source = self

        @fallback = fallback
        @allowed_error_types = allowed_error_types
        @excluded_error_types = excluded_error_types
      end

      def wait
        GitHub::RequestDurationManager.raise_if_time_budget_is_over(time_buffer_ms: GitHub::ResilienceMixin::GRACEFUL_DEGRADATION_BUFFER_MS) do
          GitHub::ResilienceMixin.tag_queries(GitHub::ResilienceMixin::PromiseWrapper::QUERY_TAG) do
            @new_promise.fulfill(@wrapped_promise.sync) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end
        end
      rescue => e # rubocop:disable Lint/GenericRescue
        graceful_error_handler = ResilienceHelper::GracefulDegradationErrorHandler.new(e, allowed_errors: allowed_error_types, excluded_errors: excluded_error_types)

        return @new_promise.reject(e) unless graceful_error_handler.degradable?

        graceful_error_handler.send_metrics("with_async_database_error_fallback", current_template)

        @new_promise.fulfill(fallback&.respond_to?(:call) ? T.unsafe(fallback).call : fallback)
      end
    end
  end
end
