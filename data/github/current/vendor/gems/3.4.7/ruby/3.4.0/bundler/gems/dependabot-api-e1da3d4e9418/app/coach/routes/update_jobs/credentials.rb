# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class Credentials < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken, type: :credentials

      requires :update_job, :token

      def call # rubocop:disable Metrics/MethodLength
        return stale_job_error unless update_job.in_state?(:enqueued, :processing)

        Renderer.resource(
          update_job,
          serializer_options: { serializer: UpdateJobCredentialsSerializer },
        )
      rescue UpdateJobCredentialsSerializer::CredentialsInvalid
        invalid_credentials_error
      rescue SecretFetcher::SecretNotFound => e
        secret_not_found_error(e)
      rescue SecretFetcher::SecretNotValid => e
        secret_not_valid_error(e)
      rescue SecretFetcher::SecretNotRetrieved => e
        secret_not_retrieved_error(e)
      rescue Octokit::UnprocessableEntity => e
        # occurs when the Dependabot integration is removed from a repository
        unprocessable_entity_error(e)
      rescue *Octokit::RATE_LIMITED_ERRORS => e
        rate_limit_error(e)
      rescue Octokit::NotFound => e
        # Seems to be a transient condition that the client can retry
        # https://github.com/github/dependabot-updates/issues/3848
        not_found_error(e)
      rescue Dependabot::ResourceUnavailableToInstallation => e
        resource_unavailable_to_installation_error(e)
      end

      private

      def invalid_credentials_error
        UpdateJobError.create!(
          update_job: update_job,
          error_type: "config_not_valid",
          error_details: { message: "Registry credentials invalid" }
        )
        Renderer.render_error(
          status: 422,
          title: "Registry credentials invalid",
          detail: "Registry configuration is not valid",
        )
      end

      def secret_not_found_error(error)
        UpdateJobError.create!(
          update_job: update_job,
          error_type: "secret_not_found",
          error_details: { "secret-name": error.message }
        )
        Renderer.render_error(
          status: 422,
          title: "Secret Not Found",
          detail: error.message,
        )
      end

      def secret_not_valid_error(error)
        UpdateJobError.create!(
          update_job: update_job,
          error_type: "secret_not_valid",
          error_details: { "secret-name": error.message }
        )
        Renderer.render_error(
          status: 422,
          title: "Secret Not Valid",
          detail: error.message,
        )
      end

      def secret_not_retrieved_error(error)
        UpdateJobError.create!(
          update_job: update_job,
          error_type: "secret_not_retrieved",
          error_details: { "secret-name": error.message }
        )
        Renderer.render_error(
          status: 422,
          title: "Secret Not Retrieved",
          detail: error.message,
        )
      end

      def unprocessable_entity_error(error)
        UpdateJobError.create!(
          update_job: update_job,
          error_type: "runner_error",
          error_details: { "message": error.message }
        )
        Renderer.render_error(
          status: 422,
          title: "Unprocessable Entity",
          detail: error.message,
        )
      end

      def rate_limit_error(error)
        UpdateJobError.create!(
          update_job: update_job,
          error_type: "octokit_rate_limited",
          error_details: { "rate-limit-reset": error.response_headers["X-RateLimit-Reset"] }
        )
        Renderer.render_error(
          status: 422,
          title: "API rate limit exceeded",
          detail: error.message,
        )
      end

      def resource_unavailable_to_installation_error(error)
        UpdateJobError.create!(
          update_job: update_job,
          error_type: "resource_unavailable_to_installation",
          error_details: { "message": error.message }
        )
        Renderer.render_error(
          status: 403,
          title: "Resource not accessible by installation",
          detail: "The resource is not available to the installation",
        )
      end

      def stale_job_error
        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "Update job has already been processed",
        )
      end

      def not_found_error(error)
        Dependabot::Logger.warn(
          msg: "Octokit raised a not found error when fetching details. This may be temporary.",
          "code.namespace": self.class.name.to_s,
          "exception.type": error.class,
          "exception.message": error.response_body,
          **update_job.telemetry_attributes,
        )
        Renderer.render_error(
          status: 500,
          title: "Unexpected error",
          detail: "Target repository was not available from the GitHub API. May be temporary.",
        )
      end
    end
  end
end
