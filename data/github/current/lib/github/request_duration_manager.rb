# typed: strict
# frozen_string_literal: true

module GitHub

  class RequestDurationManager
    extend T::Sig

    class NestedCallsNotAllowedError < StandardError; end
    class TimeBudgetIsOverError < StandardError; end

    class RequestTimeBudget
      extend T::Sig

      sig { returns(Integer) }
      attr_reader :total_window_ms

      sig { returns(Integer) }
      attr_reader :start_ms

      # This flag is used only to allow us to control the time budget control with a FF
      # Once we are confident that the feature is stable, we can remove this flag
      sig { returns(T::Boolean) }
      attr_accessor :enabled

      sig { params(total_window_ms: Integer).void }
      def initialize(total_window_ms:)
        @total_window_ms = total_window_ms
        @start_ms = T.let(Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond).to_i, Integer)
        @enabled = T.let(false, T::Boolean)
      end

    end

    # This is the key used to store/retrieve the time budget
    REQUEST_TIME_BUDGET_KEY = "REQUEST_TIME_BUDGET"

    sig { params(total_window_ms: Integer, block: T.proc.void).returns(T.untyped) }
    def self.with_budget_control(total_window_ms:, &block)
      if request_time_budget.present?
        raise GitHub::RequestDurationManager::NestedCallsNotAllowedError
      end

      start(total_window_ms: total_window_ms)

      block.call
    ensure
      clear
    end

    # Raises an exception if the time budget for the web request exceeds the time_buffer_ms.
    #
    # This method is used to ensure that we don't exceed the time budget for a web request.
    # If the time budget is exceeded, the method raises a `GitHub::RequestDurationManager::TimeBudgetIsOverError`.
    # Otherwise, it will yield the remaining time budget to the block.
    #
    # Note: In case this method runs in a Job context, or others that are not currently budgeted,
    # the remaining time budget will be `nil`.
    #
    # @example
    #   It can be used in combination with MySQL `MAX_EXECUTION_TIME` optimizer hint hint to ensure
    #   that a query won't exhaust a desired time budget.
    #
    #   org_repositories = GitHub::RequestDurationManager.raise_if_time_budget_is_over(time_buffer_ms: 2000) do |remaining_time_budget_ms|
    #      Repository.where(organization:).limit_execution_time(limit_ms: remaining_time_budget_ms)
    #   end
    #
    #   Note: that the remaining_time_budget_ms is computed only once per block invocation. So, if you want to
    #   use it in multiple queries, you should wrap each query in a separate block.
    #
    # @param time_buffer_ms [Integer] the time buffer in milliseconds.
    # @param block [Proc] the block to be executed if the time budget is not over.
    # @raise [GitHub::RequestDurationManager::TimeBudgetIsOverError] if the time budget is over.
    sig do
      params(
        time_buffer_ms: Integer,
        block: T.nilable(T.proc.params(remaining_time_budget_ms: T.nilable(Integer)
      ).returns(T.untyped))).returns(T.untyped)
    end
    def self.raise_if_time_budget_is_over(time_buffer_ms:, &block)
      if budgeted?

        remaining_time_budget_ms = remaining_time_ms - time_buffer_ms

        # The time is up, short-circuit the execution
        raise GitHub::RequestDurationManager::TimeBudgetIsOverError if remaining_time_budget_ms <= 0

        return yield(remaining_time_budget_ms) if block_given?
        return
      end

      yield(nil) if block_given?
    end

    sig { returns(Integer) }
    def self.remaining_time_ms
      (total_window_ms - elapsed_time_ms)
    end

    sig { returns(Integer) }
    def self.elapsed_time_ms
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond).to_i
      (now - start_ms)
    end

    sig { returns(T::Boolean) }
    def self.budgeted?
      return false unless time_budget_control_enabled?

      self.start_ms.present? && self.total_window_ms.present?
    end

    sig { returns(T::Boolean) }
    def self.time_budget_control_enabled?
      !!request_time_budget&.enabled
    end

    sig { void }
    def self.enable_time_budget_control
      return unless request_time_budget.present?

      T.must(request_time_budget).enabled = true
    end

    sig { returns(T.nilable(RequestTimeBudget)) }
    def self.request_time_budget
      Thread.current[REQUEST_TIME_BUDGET_KEY]
    end
    private_class_method :request_time_budget

    sig { returns(Integer) }
    def self.total_window_ms
      T.must(request_time_budget).total_window_ms
    end
    private_class_method :total_window_ms

    sig { returns(Integer) }
    def self.start_ms
      T.must(request_time_budget).start_ms
    end
    private_class_method :start_ms

    sig { params(total_window_ms: Integer).void }
    def self.start(total_window_ms:)
      Thread.current[REQUEST_TIME_BUDGET_KEY] = GitHub::RequestDurationManager::RequestTimeBudget.new(total_window_ms: total_window_ms)
    end
    private_class_method :start

    sig { void }
    def self.clear
      Thread.current[REQUEST_TIME_BUDGET_KEY] = nil
    end
    private_class_method :clear

  end
end
