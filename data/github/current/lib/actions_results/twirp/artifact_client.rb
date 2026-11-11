# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module ActionsResults
  module Twirp
    class ArtifactClient < ActionsResults::Twirp::BaseClient
      # We keep this API to fetch one artifact-level signed URL so callers can
      # perform byte-range reads for file extraction without downloading through dotcom.
      sig do
        params(
          workflow_run_backend_id: String,
          workflow_job_run_backend_id: String,
          name: String
        ).returns(TwirpResponse)
      end
      def get_download_url_for_artifact(workflow_run_backend_id:, workflow_job_run_backend_id:,  name:)
        rpc(
          :GetDownloadURLForArtifact,
          workflow_run_backend_id: workflow_run_backend_id,
          workflow_job_run_backend_id: workflow_job_run_backend_id,
          name: name,
        )
      end

      # Existing artifact delete behavior is unchanged and remains in the same
      # client so callers use a single ArtifactResultsAPI entry point.
      sig do
        params(
          workflow_run_backend_id: String,
          workflow_job_run_backend_id: String,
          name: String
        ).returns(TwirpResponse)
      end
      def delete_artifact(workflow_run_backend_id:, workflow_job_run_backend_id:, name:)
        rpc(
          :DeleteArtifact,
          workflow_run_backend_id: workflow_run_backend_id,
          workflow_job_run_backend_id: workflow_job_run_backend_id,
          name: name,
        )
      end

      # We list archive entries up front to power browse UI and local pagination.
      sig do
        params(
          workflow_run_backend_id: String,
          workflow_job_run_backend_id: String,
          name: String
        ).returns(TwirpResponse)
      end
      def list_artifact_files(workflow_run_backend_id:, workflow_job_run_backend_id:, name:)
        rpc(
          :ListArtifactFiles,
          workflow_run_backend_id: workflow_run_backend_id,
          workflow_job_run_backend_id: workflow_job_run_backend_id,
          name: name,
        )
      end

      # This RPC provides per-file metadata when available. Callers still layer
      # their own fallback because not all local environments expose this route.
      sig do
        params(
          workflow_run_backend_id: String,
          workflow_job_run_backend_id: String,
          name: String,
          file_path: String
        ).returns(TwirpResponse)
      end
      def get_artifact_file_download_url(workflow_run_backend_id:, workflow_job_run_backend_id:, name:, file_path:)
        rpc(
          :GetArtifactFileDownloadURL,
          workflow_run_backend_id: workflow_run_backend_id,
          workflow_job_run_backend_id: workflow_job_run_backend_id,
          name: name,
          file_path: file_path,
        )
      end

      private

      # Artifact file browsing is implemented against ArtifactResultsAPI methods.
      def twirp_class
        ::MonolithTwirp::ActionsResults::Core::V1::ArtifactResultsAPIClient
      end
    end
  end
end
