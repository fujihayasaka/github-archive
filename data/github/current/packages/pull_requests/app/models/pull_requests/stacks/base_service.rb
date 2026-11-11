# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    # Abstract base class for stacked PR service objects.
    #
    # Provides shared telemetry infrastructure (Datadog metrics, structured
    # logging, exception recording) and a `call`→`perform` wrapper so that
    # children only need to implement the business logic in `perform`.
    #
    # Each child must:
    #   1. Fix the `ResultType` type member to its own `Result` type alias.
    #   2. Implement the four abstract hooks: `metric_key`, `human_name`,
    #      `service_log_context`, and `perform`.
    #   3. Call `super(log_context:)` from its constructor.
    #
    # Metrics are emitted as `pull_request_stacks.{metric_key}.complete`
    # with an `outcome:` tag.  Detailed failure information (reason, exception
    # class, affected PR numbers) goes into structured logs only.
    class BaseService
      extend T::Helpers
      extend T::Generic
      abstract!

      ResultType = type_member

      sig { params(log_context: T::Hash[String, String]).void }
      def initialize(log_context: {})
        @log_context = T.let(log_context, T::Hash[String, String])
      end

      # Short identifier used in metric names and structured log keys.
      # Examples: "creation", "unstack", "update_pulls".
      sig { abstract.returns(String) }
      def metric_key; end

      # Human-readable label used as the log message prefix.
      # Examples: "Stack creation", "Unstack pulls".
      sig { abstract.returns(String) }
      def human_name; end

      # Child-specific entries merged into every log line (repo id, stack id, etc.).
      sig { abstract.returns(T::Hash[String, T.untyped]) }
      def service_log_context; end

      # The actual business logic.  Children implement this instead of `call`.
      sig { abstract.returns(ResultType) }
      def perform; end

      sig { returns(ResultType) }
      def call
        perform
      rescue => e
        record_exception(e)
        raise
      end

      private

      # Core telemetry method.  Increments a Datadog counter and emits a
      # structured log line.  Only the `outcome:` tag is sent to Datadog;
      # everything else goes into the log.
      sig { params(outcome: String, extra_log: T::Hash[String, T.untyped]).void }
      def record_outcome(outcome, extra_log: {})
        GitHub.dogstats.increment(
          "pull_request_stacks.#{metric_key}.complete",
          tags: ["outcome:#{outcome}"],
        )
        GitHub.logger.info(
          "#{human_name} #{outcome}",
          log_context.merge(
            "gh.pull_request_stacks.#{metric_key}.outcome" => outcome,
          ).merge(extra_log),
        )
      end

      # Builds an Error struct, records a failure outcome, and returns the Error.
      sig do
        params(
          reason: Error::FailureReason,
          pulls: T.nilable(T::Array[PullRequest]),
          exception: T.nilable(Exception),
          details: T::Hash[String, String],
        ).returns(Error)
      end
      def logged_error_result(reason, pulls: nil, exception: nil, details: {})
        result = Error.new(reason:, pulls:, exception:)

        extra_log = T.let({
          "gh.pull_request_stacks.#{metric_key}.failure_reason" => reason.serialize,
          "gh.pull_request_stacks.#{metric_key}.failure_message" => result.message,
        }, T::Hash[String, T.untyped])
        extra_log.merge!(details)

        if exception
          extra_log["error.class"] = exception.class.name
          extra_log["error.message"] = exception.message
        end

        if pulls.present?
          extra_log["gh.pull_request.numbers"] = pulls.map(&:number).join(",")
        end

        record_outcome("failure", extra_log:)
        result
      end

      # Records a success outcome.  Children call this, then return their own
      # success value.
      sig { params(extra_log: T::Hash[String, T.untyped]).void }
      def record_success_outcome(extra_log: {})
        record_outcome("success", extra_log:)
      end

      # Records an unhandled-exception outcome.
      sig { params(error: StandardError).void }
      def record_exception(error)
        record_outcome("exception", extra_log: {
          "error.class" => error.class.name,
          "error.message" => error.message,
        })
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def log_context
        @log_context.reverse_merge(
          "code.namespace" => self.class.name,
          "code.function" => "#call",
        ).merge(service_log_context)
      end
    end
  end
end
