# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Pages
  module Pagesdeployerapi
    module V1
      class GetArtifactDownloadUrl
        attr_reader :req, :env

        def self.call(request, env)
          new(request, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          return Twirp::Error.not_found("artifact does not exist", argument: "artifact_id") unless artifact
          return Twirp::Error.not_found("artifact must originate from results service", argument: "artifact_id") unless artifact.is_results_artifact?
          return Twirp::Error.not_found("artifact has expired", argument: "artifact_id") if artifact.expired?

          results_ids = artifact.get_results_ids_from_source_url
          return Twirp::Error.not_found("unable to parse result IDs from source URL", argument: "artifact_id") unless results_ids

          result = ActionsResults::Twirp.artifact_client.get_download_url_for_artifact(
            workflow_job_run_backend_id: results_ids[:workflow_job_run_backend_id],
            workflow_run_backend_id: results_ids[:workflow_run_backend_id],
            name: artifact.name,
          )
          return Twirp::Error.internal("failed to generate URL to download artifact") unless result.call_succeeded?

          artifact_url = result.value&.url
          if artifact_url
            { download_url: artifact_url }
          else
            log_error("No artifact URL returned when calling results service for download URL")
            {}
          end
        end

        private

        def artifact
          @artifact ||= Artifact.find_by(repository_id: @req.repository_id, id: @req.artifact_id)
        end

        def log_error(message)
          GitHub.logger.error(
            message,
            "code.namespace" => "Deployer::V1::GetArtifactDownloadUrl",
            "code.function" => "call",
            "gh.repo.id" => @req.repository_id,
            "gh.artifact.id" => @req.artifact_id
          )
        end
      end
    end
  end
end
