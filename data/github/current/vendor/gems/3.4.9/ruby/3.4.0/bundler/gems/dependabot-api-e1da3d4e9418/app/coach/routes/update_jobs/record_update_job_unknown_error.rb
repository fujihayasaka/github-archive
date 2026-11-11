# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class RecordUpdateJobUnknownError < Coach::Middleware
      ERROR_DETAILS_MAX_CHARS = 65_535
      ERROR_DETAILS_TRUNC_CHARS = 6500

      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing

      uses Middlewares::CheckParams,
           "data.error-type" => { type: String, required: true },
           "data.error-details" => { type: [Hash, NilClass] }

      requires :update_job

      def call
        log_errors if update_job.update_config.repo.config_feature_enabled?(:log_unknown_errors)
        report_error_to_failbot if should_report_updater_error?

        create_unknown_error unless error_exists?
        Renderer.no_content
      end

      private

      # rubocop:disable Metrics/PerceivedComplexity
      def log_errors
        log_details = {
          msg: "Unknown error",
          "code.namespace": self.class.name.to_s,
          "gh.dependabot_api.update_job_error.error_type": error_type,
          "exception.type": error_details&.fetch("error-class", nil),
          "exception.message": error_details&.fetch("error-message", nil)&.tr("\n", " "),
          "exception.stacktrace": error_details&.fetch("error-backtrace", nil)&.split("\n"),
          "gh.dependabot_api.update_config.package_manager": error_details&.fetch("package-manager", nil),
          job_dependencies: error_details&.fetch("job-dependencies", nil),
          job_dependency_group: error_details&.fetch("job-dependency_group", nil),
          **update_job.telemetry_attributes,
        }
        Dependabot::Logger.error(log_details)
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def create_unknown_error
        UpdateJobUnknownError.create!(
          update_job: update_job,
          error_type: error_type,
          error_details: truncated_error_details,
        )
      end

      # This isn't race safe, but we don't really care about duplicate errors.
      # Making this race safe would probably require moving away from using a
      # JSON column for error_details
      def error_exists?
        update_job.
          update_job_unknown_errors.
          where(error_type: error_type).
          any? { |err| err.error_details.to_json == error_details.to_json }
      end

      def truncated_error_details
        return error_details if error_details.to_json.length < ERROR_DETAILS_MAX_CHARS

        # If the overall error_details JSON exceeds the character limit, we truncate
        # each value to a maximum value to permit approximately ten fields in the
        # worst case.
        #
        # We generally expect the error_details to have just a `message` key
        # most of the time, but the datastructure is freeform so the truncation
        # optimises for least risk of rejecting an error from the runner.
        error_details.each_with_object({}) do |(key, value), obj|
          val = value.to_s.truncate(ERROR_DETAILS_TRUNC_CHARS)
          obj[key] = val
        end
      end

      def error_type
        params.fetch(:data).fetch(:"error-type")
      end

      def error_details
        params.fetch(:data).fetch(:"error-details")
      end

      def should_report_updater_error?
        !Dependabot.proxima?
      end

      def report_error_to_failbot
        updater_error = UpdaterError.new(error_details)

        ::Dependabot::Exceptions.report(updater_error, update_job.telemetry_attributes)
      end
    end
  end
end
