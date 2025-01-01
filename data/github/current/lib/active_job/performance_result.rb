# typed: false
# frozen_string_literal: true

require "active_job/exceptions"

module ActiveJob
  # Hooks into Active Job to allow categorization of a job performance, in time
  # for job instrumentation and delivery to Datadog.
  module PerformanceResult
    ABORTED = :aborted # Halted by a callback via throw :abort
    DISCARDED = :discarded # Discarded by discard_on or retry_on with no exception raised
    FAILED = :failed # Raised an exception and was not retried
    RESCUED = :rescued # Exception was raised, rescued, and not re-raised
    RETRIED = :retried # Failed and a retry was enqueued, swallowing the exception
    SUCCEEDED = :succeeded # Performed successfully with no exception raised

    extend ActiveSupport::Concern

    included do
      # Categorizes job execution by one of the Symbol constants defined above.
      # May be nil before the result of the job's performance is determined.
      attr_accessor :performance_result

      # Tracks the exception object that was rescued for a job with a result
      # of discarded, rescued, or retried. This is especially helpful for
      # observing the error class that caused a job to be retried, since the
      # active_job.performed and active_job.perform.dist.time metrics aren't
      # tagged with the "error" tag until retries are exhausted.
      attr_accessor :handled_error

      # Hook into Active Job's exception handling, which is included into
      # ActiveJob::Base before its intstrumentation functionality. This allows
      # PerformanceResult to calculate and set the result of the job's
      # performance before instrumentation is triggered, giving subscribers
      # access to Job#performance_result.
      ActiveJob::Exceptions.prepend(PerformanceResult::Exceptions)
    end

    module Exceptions
      def perform_now(...)
        self.performance_result = nil

        super.tap do
          # If no other hook has set the result, the absence of a raised
          # exception implies success.
          self.performance_result ||= SUCCEEDED
        end
      # This aggressive rescue mirrors ActiveJob::Exceptions#perform_now
      # and will always re-raise.
      rescue Exception # rubocop:disable Lint/GenericRescue
        self.performance_result = FAILED
        self.handled_error = nil # Not considered "handled" since we re-raise
        raise
      end

      def run_after_discard_procs(...)
        super.tap do
          # Set the result to discarded when discarding a job. This result may
          # be overridden in #perform_now if an exception is raised.
          self.performance_result ||= DISCARDED
        end
      end

      def retry_job(...)
        super.tap do
          # When the job is instructed to retry itself, set the result to
          # retried, before "perform.active_job" instrumentation is triggered.
          self.performance_result ||= RETRIED
        end
      end

      def rescue_with_handler(error, ...)
        super.tap do
          # Rescuing an exception via rescue_with, retry_on, or discard_on will
          # initially set the result to rescued if it hasn't already been set
          # to retried or discarded, as retry_on and discard_on will do.
          self.performance_result ||= RESCUED
          self.handled_error = error
        end
      end

      def halted_callback_hook(...)
        super.tap do
          # If job execution is halted by one of its callbacks, set the result
          # to aborted.
          self.performance_result ||= ABORTED
        end
      end
    end
  end
end
