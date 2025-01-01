# typed: false
# frozen_string_literal: true

require_relative "transient_error_resiliency_helpers"

module GitHub
  module StreamProcessors
    module TransientErrorResiliency
      extend ActiveSupport::Concern
      include TransientErrorResiliencyHelpers

      DEFAULT_TRANSIENT_ERROR_PAUSE_DURATION = 2.minutes
      attr_writer :transient_error_pause_duration
      DEFAULT_TRANSIENT_ERROR_MAX_RETRIES = 3
      attr_writer :transient_error_max_retries

      included do
        set_callback :message, :around, :pause_on_transient_errors
        set_callback :message, :around, :retry_on_transient_errors
      end

      private

      def retry_on_transient_errors
        attempts = 0

        begin
          yield
        rescue => error # rubocop:disable Lint/RescueException
          if attempts < transient_error_max_retries && TRANSIENT_ERRORS_TO_RETRY_ON.any? { |error_class, proc| error.is_a?(error_class) && proc.call(error) }
            attempts += 1
            stats.increment("github.stream_processors.transient_error.retry", tags: default_stats_tags + ["attempts:#{attempts}", "error:#{error.class}"])
            log_retry(error, attempts)
            sleep attempts
            retry
          else
            raise
          end
        end
      end

      def pause_on_transient_errors
        yield
      rescue => error # rubocop:disable Lint/RescueException
        if pause_on_transient_errors?(error)
          report_error(error)

          stats.increment("github.stream_processors.transient_error.pause", tags: default_stats_tags + ["error:#{error.class}"])
          pause(expires: transient_error_pause_duration(error).from_now, reason: "Transient error: #{error.class}")
        else
          raise
        end
      end

      # Internal: Duration to pause for when a transient error is encountered. Note that this can be overridden by
      # processor implementations to provide a more fine-grained control over the pause duration for different errors.
      #
      # Returns ActiveSupport::Duration
      sig { overridable.params(error: StandardError).returns(ActiveSupport::Duration) }
      def transient_error_pause_duration(error)
        @transient_error_pause_duration || DEFAULT_TRANSIENT_ERROR_PAUSE_DURATION
      end

      # Internal: Number of retries of transient errors to attempt before re-raising
      #
      # Returns Integer
      def transient_error_max_retries
        @transient_error_max_retries || DEFAULT_TRANSIENT_ERROR_MAX_RETRIES
      end

      def log_retry(error, attempts)
        context = current_error_context || {}
        context = context.merge(
          "code.namespace" => self.class.name,
          "code.function" => "retry_on_transient_errors",
          "gh.processor.name" => self.class.name,
          "gh.catalog_service" => logical_service,
          "gh.processor.retry.attempts" => attempts,
          "exception.stacktrace" => error.backtrace.to_s
        )
        GitHub.logger.error(error, context)
      end
    end
  end
end
