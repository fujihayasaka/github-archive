# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class RecordUpdateJobError < Coach::Middleware
      ERROR_DETAILS_MAX_CHARS = 65_535
      ERROR_DETAILS_TRUNC_CHARS = 6500
      SECRET_NOT_FOUND_TITLE = '"title":"Secret Not Found"'

      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams,
           "data.error-type" => { type: String, required: true },
           "data.error-details" => { type: [Hash, NilClass] }

      requires :update_job

      def call
        Dependabot::Exceptions.push(
          "gh.dependabot_api.update_job_error.error_type": error_type
        )

        create_update_job_error unless error_exists?
        Renderer.no_content
      end

      private

      def create_update_job_error
        UpdateJobError.create!(
          update_job: update_job,
          error_type: error_type,
          error_details: truncated_error_details,
        )
      end

      # This isn't race safe, but we don't really case about duplicate errors.
      # Making this race safe would probably require moving away from using a
      # JSON column for error_details
      def error_exists?
        update_job.
          update_job_errors.
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
        mapped_error[:type]
      end

      def error_details
        mapped_error[:details]
      end

      def mapped_error
        @mapped_error ||= ErrorMapper.new.map_error({
                                                      type: params.fetch(:data).fetch(:"error-type"),
                                                      details: params.fetch(:data).fetch(:"error-details"),
                                                    }, update_job)
      end

      class ErrorMapper
        def map_error(error, update_job)
          mapped_error = adjust_error(error, update_job)
          if error[:type] != mapped_error[:type]
            update_job.increment_metric("update_job.mapped_error",
                                        tags: { from: error[:type], to: mapped_error[:type] })
          end
          mapped_error
        end

        private

        def adjust_error(error, update_job)
          return github_authentication_error(update_job) if user_caused_octokit_unauthorized_error?(error, update_job)
          return error unless secret_not_found_error?(error)

          secret_name = extract_secret_name(error[:details][:message] || error[:details][:'action-error'])
          if secret_name.nil?
            Dependabot::Exceptions.report(RuntimeError.new("Couldn't extract secret name from SecretNotFound error"))
            return error
          end

          {
            type: "secret_not_found",
            details: { "secret-name" => secret_name },
          }
        end

        # This error is returned by Routes::UpdateJobs::Credentials and then reported back
        # as a "runner_error" by the update-job-runner.
        def secret_not_found_error?(error)
          case error[:type]
          when "runner_error"
            return false unless error[:details].key?(:message)

            return error[:details][:message].include?(SECRET_NOT_FOUND_TITLE)
          when "actions_workflow_updater"
            return false unless error[:details].key?(:'action-error')

            return error[:details][:'action-error'].include?(SECRET_NOT_FOUND_TITLE)
          end

          false
        end

        def extract_secret_name(message)
          matches = message.match(/"detail":"(?<secret_name>[^"]+)"/)
          matches && matches[:secret_name]
        end

        def user_caused_octokit_unauthorized_error?(error, update_job)
          return false unless error[:type] == "octokit_unauthorized"

          update_job.update_config.find_registry_by(
            type: :git_source,
            host: Dependabot::Application.target_github_hostname(update_job.repo.account)
          ).present?
        end

        def github_authentication_error(update_job)
          {
            type: "private_source_authentication_failure",
            details: { "source" => Dependabot::Application.target_github_hostname(update_job.repo.account) },
          }
        end
      end
    end
  end
end
