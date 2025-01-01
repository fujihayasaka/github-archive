# typed: true
# frozen_string_literal: true

class Api::Artifacts < Api::App
  include ReceiveSchemaWithOpenApi
  include ActionsHelper

  # Get all artifacts for a run.
  get "/repositories/:repository_id/actions/runs/:run_id/artifacts", operation_id: "actions/list-workflow-run-artifacts" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workflow_run = Actions::WorkflowRun.find_by(id: params[:run_id])
    deliver_error!(404) unless workflow_run

    deliver_error!(404) unless repo.id == workflow_run.repository_id

    check_suite = workflow_run.check_suite
    deliver_error!(404) unless check_suite

    artifacts = check_suite.artifacts.includes(check_suite: :repository)
    artifacts = artifacts.where(name: params[:name]) if params[:name].present?

    artifacts = paginate_rel(artifacts)

    deliver :artifacts_hash, { artifacts: artifacts, total_count: artifacts.total_entries, repository: repo, workflow_run: workflow_run }
  end

  # Get an artifact.
  get "/repositories/:repository_id/actions/artifacts/:artifact_id", operation_id: "actions/get-artifact" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    artifact = Artifact.includes(:check_suite).find_by(id: params[:artifact_id])
    deliver_error!(404) unless artifact

    deliver_error!(404) unless repo.id == artifact.repository_id

    deliver :artifact_hash, { artifact: artifact, repository: repo }
  end

  # Get all artifacts for a repository.
  get "/repositories/:repository_id/actions/artifacts", operation_id: "actions/list-artifacts-for-repo" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    name_present = params[:name].present?

    artifacts = if name_present
      Artifact.where(repository_id: repo.id)
        .where(name: params[:name])
        .includes(:check_suite, check_suite: :workflow_run)
        .order(id: :desc)
    else
      Artifact.from("artifacts FORCE INDEX(index_artifacts_on_repository_id_and_id)")
        .where(repository_id: repo.id)
        .includes(:check_suite, check_suite: :workflow_run)
        .order(id: :desc)
    end

    artifacts = paginate_rel(artifacts)
    deliver :artifacts_hash, { artifacts: artifacts, total_count: artifacts.total_entries, repository: repo }
  end

  # Download the zip archive of an artifact.
  get "/repositories/:repository_id/actions/artifacts/:artifact_id/zip", operation_id: "actions/download-artifact" do
    repo = find_repo!

    control_access :read_actions_downloads,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "You must have the actions scope to download artifacts.",
      allow_integrations: true,
      allow_user_via_granular_actor: true

    artifact = Artifact.includes(:check_suite).find_by(id: params[:artifact_id])
    deliver_error!(404) unless artifact

    deliver_error! 410, message: "Artifact has expired" if artifact.expired?

    deliver_error!(404) unless repo.id == artifact.repository_id && artifact.check_suite.present?

    if artifact.is_results_artifact?
      results_ids = artifact.get_results_ids_from_source_url
      deliver_error!(404) unless results_ids

      result = ActionsResults::Twirp.artifact_client.get_download_url_for_artifact(
        workflow_job_run_backend_id: results_ids[:workflow_job_run_backend_id],
        workflow_run_backend_id: results_ids[:workflow_run_backend_id],
        name: artifact.name,
      )

      deliver_error! 500, message: "Failed to generate URL to download artifact" unless result.call_succeeded? && result.value&.ok

      artifact_url = result.value&.url
      deliver_error! 500, message: "Failed to generate URL to download artifact" unless artifact_url

      redirect artifact_url
    else
      request = GitHub::Launch::Services::Artifactsexchange::ExchangeURLRequest.new({
        unauthenticated_url: artifact.source_url,
        repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(repo)),
        resource_type: GitHub::Launch::Services::Artifactsexchange::ResourceType::TYPE_DOWNLOAD_ARTIFACT,
      })

      check_suite = artifact.check_suite
      deliver_error!(404) unless check_suite

      result = Launch::Twirp.artifacts_exchange_client_for_check_suite(check_suite).exchange_url(request)

      if result.call_succeeded?
        redirect result.value.authenticated_url
      elsif result.status == 404
        # Returning 410 instead of 404, since dotcom record still exists for this artifact
        deliver_error! 410, message: "This artifact was either expired or deleted"
      else
        deliver_error! 500, message: "Failed to generate URL to download artifact"
      end
    end
  end

  # Delete an artifact.
  delete "/repositories/:repository_id/actions/artifacts/:artifact_id", operation_id: "actions/delete-artifact" do
    repo = find_repo!

    receive_with_schema("artifact", "delete-artifact")

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      forbid_message: "You must have push access to this repository.",
      allow_integrations: true,
      allow_user_via_granular_actor: true

    artifact = Artifact.find_by(id: int_id_param!(key: :artifact_id))
    deliver_error!(404) unless artifact

    deliver_error!(404) unless repo.id == artifact.repository_id

    artifact.destroy
    deliver_empty status: 204
  end
end
