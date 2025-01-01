# typed: strict
# frozen_string_literal: true

require "trino-client"

# This module provides opinionated retry logic that can be used for jobs in
# the DependencyGraph module.
#
# The following constants cannot be overridden in subclasses at the moment.
# In case you need to override them, please do not include this module and
# implement the retry logic in your job class.
#
# The module also provides basic telemetry for the job execution, including
# success and failure metrics, as well as error reporting using Failbot.
#
module DependencyGraph
  module RetryJob
    extend T::Helpers
    abstract!

    requires_ancestor { ApplicationJob }

    DEFAULT_RETRY_ATTEMPTS = 5

    FRENO_RETRY_ATTEMPTS = 10

    METRICS_PREFIX = "dependency_graph.jobs"

    RETRYABLE_ERRORS = [
      ActiveRecord::Deadlocked,
      Trino::Client::TrinoError
    ].freeze

    RETRYABLE_FRENO_ERRORS = [
      Freno::Throttler::Error,
      Freno::Error,
      Freno::Throttler::WaitedTooLong,
    ].freeze

    NON_RETRYABLE_ERRORS = [
      StandardError,
      ArgumentError
    ].freeze

    sig { params(base: Module).void }
    def self.included(base)
      T.unsafe(base).retry_on_dirty_exit do |_, error|
        GitHub.logger.error("Job retrying on dirty exit", T.unsafe(self).logging_context.merge(
          "error.name" => error.class.name,
          "error.message" => error.respond_to?(:message) ? error.message : ""
        ))
      end

      T.unsafe(base).retry_on_recoverable_exceptions do |_, error|
        GitHub.logger.error("Job retrying recoverable exception", T.unsafe(self).logging_context.merge(
          "error.name" => error.class.name,
          "error.message" => error.respond_to?(:message) ? error.message : ""
        ))
      end

      # Retry on retryable exceptions
      T.unsafe(base).retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: DEFAULT_RETRY_ATTEMPTS) do |job, error|
        GitHub.dogstats.increment(
          "#{METRICS_PREFIX}.retries_exhausted",
          tags: [*job.all_stats_tags, "job:#{job.class.to_s.underscore}", "error:#{error.class.to_s.underscore}"]
        )
        job.on_retries_exhausted(error, retried: true)
      end

      # Retry on retryable Freno exceptions
      T.unsafe(base).retry_on(*RETRYABLE_FRENO_ERRORS, wait: :polynomially_longer, attempts: FRENO_RETRY_ATTEMPTS) do |job, error|
        GitHub.dogstats.increment(
          "#{METRICS_PREFIX}.retries_exhausted",
          tags: [*job.all_stats_tags, "job:#{job.class.to_s.underscore}", "error:#{error.class.to_s.underscore}"]
        )
        job.on_retries_exhausted(error, retried: true)
      end

      # Code executed around the job execution.
      T.unsafe(base).around_perform do |job, block|
        block.call
        GitHub.dogstats.increment("#{METRICS_PREFIX}.execution", tags: job.all_stats_tags + ["status:success"])
      rescue *RETRYABLE_ERRORS, *RETRYABLE_FRENO_ERRORS => ex
        GitHub.logger.error("Job failed with retriable error", T.unsafe(self).logging_context.merge(
          "error.name" => ex.class.name,
          "error.message" => ex.respond_to?(:message) ? ex.message : ""
        ))

        # raising the error again to be retried
        raise ex
      rescue *NON_RETRYABLE_ERRORS => ex
        job.on_retries_exhausted(ex)
      ensure
        job.ensure_execute
      end
    end

    # This method is called when the job error is not retryable or has exhausted all retries.
    sig { params(error: Exception, retried: T::Boolean).void }
    def on_retries_exhausted(error, retried: false)
      GitHub.logger.error("Job execution failed", T.unsafe(self).logging_context.merge(
        "error.name" => error.class.name,
        "error.message" => error.respond_to?(:message) ? error.message : "",
        "error.retried" => retried
      ))

      GitHub.dogstats.increment(
        "#{METRICS_PREFIX}.execution",
        tags: [
          *T.unsafe(self).all_stats_tags,
          "cause:exception",
          "exception:#{error.class.name}",
          "retried:#{retried}",
          "status:failure"
        ]
      )

      Failbot.report(error, T.unsafe(self).failbot_context.merge(retried: retried))

      # allow the job to be redelivered
      Kernel.raise error
    end

    # This method will be called after every execution of the job.
    # It runs within an `ensure` block.
    # Override it if you need a custom cleanup for your job.
    sig { void }
    def ensure_execute
    end
  end
end
