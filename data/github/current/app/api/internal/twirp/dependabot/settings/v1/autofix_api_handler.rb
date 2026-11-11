# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependabot-settings"

module Api::Internal::Twirp::Dependabot
  module Settings
    module V1
      # Handler for MonolithTwirp::Dependabot::Settings::V1::AutofixAPIService.
      class AutofixAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["dependabot_api"]
        handles_service MonolithTwirp::Dependabot::Settings::V1::AutofixAPIService

        resolve_tenant_context do |req, _env|
          repository = ::Repositories::Public.find_active(req.repository_id)
          next repository.owner&.business if repository.present?
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        # Public: Implementation of the CreateSuggestedFixAnnotation Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Dependabot::Settings::V1::CreateSuggestedFixAnnotationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Dependabot::Settings::V1::CreateSuggestedFixAnnotationResponse, or a Twirp::Error.
        def create_suggested_fix_annotation(req, env)
          return Twirp::Error.invalid_argument("must be provided", argument: "repository_id") unless req.repository_id.present? && req.repository_id.nonzero?
          return Twirp::Error.invalid_argument("must be provided", argument: "pull_request_number") unless req.pull_request_number.present? && req.pull_request_number.nonzero?
          return Twirp::Error.invalid_argument("must be provided", argument: "autofix_job_id") unless req.autofix_job_id.present? && req.autofix_job_id.nonzero?
          return Twirp::Error.invalid_argument("must be provided", argument: "check_run_id") unless req.check_run_id.present? && req.check_run_id.nonzero?
          return Twirp::Error.invalid_argument("must be provided", argument: "annotation_location") unless req.annotation_location.present?

          repository = ::Repositories::Public.find_active(req.repository_id)

          return Twirp::Error.not_found("Repository ID '#{req.repository_id}' not found.") unless repository
          return Twirp::Error.permission_denied("feature not available") unless autofix_enabled_on_repository?(repository)

          CreateDependabotAnnotationsJob.perform_later(
            repository_id: req.repository_id,
            pull_request_number: req.pull_request_number,
            autofix_job_id: req.autofix_job_id,
            annotation_location: req.annotation_location.to_h,
            check_run_id: req.check_run_id,
            level: req.level,
            message: req.message,
          )

          { id: req.autofix_job_id, success: true }
        end

        def autofix_enabled_on_repository?(repo)
          return false if GitHub.single_tenant_enterprise?

          repo.dependabot_autofix_enabled?
        end
      end
    end
  end
end
