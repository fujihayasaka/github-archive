# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module ActionsResults
  module Twirp
    class ArtifactClient < ActionsResults::Twirp::BaseClient
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

      private

      def twirp_class
        ::MonolithTwirp::ActionsResults::Core::V1::ArtifactResultsAPIClient
      end
    end
  end
end
