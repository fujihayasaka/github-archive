# typed: false
# frozen_string_literal: true

class Api::DeploymentRequests < Api::App
  include ReceiveSchemaWithOpenApi

  PendingDeploymentsQuery = Api::App::PlatformClient.parse <<~'GRAPHQL'
    query($workflowRunId: ID!, $includeFullTeamDetails: Boolean!, $skipImmediateRepositories: Boolean!) {
      node(id: $workflowRunId) {
        ... on WorkflowRun {
          pendingDeploymentRequests(first: 100) {
            nodes {
              ...Api::Serializer::DeploymentRequestsDependency::DeploymentRequestsFragment
            }
          }
        }
      }
    }
  GRAPHQL

  # currently retrieves a list of only `manual_approver` gates that are pending
  get "/repositories/:repository_id/actions/runs/:run_id/pending_deployments", operation_id: "actions/get-pending-deployments-for-run" do
    repo = find_repo!
    deliver_error! 404 unless repo.can_use_environments_api?

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    workflow_run = find_workflow_run(repo)

    variables = {
      "workflowRunId" => workflow_run.global_relay_id,
      "includeFullTeamDetails" => false,
      "skipImmediateRepositories" => true
    }

    results = platform_execute(PendingDeploymentsQuery, variables: variables)

    if has_any_graphql_errors?(results)
      deliver_graphql_error({
        errors: results.errors.all,
        resource: "DeploymentRequests",
        documentation_url: @documentation_url
      })
    end

    deployment_requests = results.data.node.pending_deployment_requests.nodes

    deliver :graphql_deployment_request_hash, deployment_requests, { repo: workflow_run.repository }
  end

  # allows a user to approve or reject a pending `manual_approval` gate.
  post "/repositories/:repository_id/actions/runs/:run_id/pending_deployments", operation_id: "actions/review-pending-deployments-for-run" do
    repo = find_repo!
    deliver_error!(404) unless repo.can_use_environments_api?

    control_access :approve_deployments,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    workflow_run = find_workflow_run(repo)
    data = receive_with_schema("deployment-review", "review")

    pending_gate_requests = workflow_run.check_suite.pending_approval_gate_requests_in_environments(current_user, data["environment_ids"])
    deployments = pending_gate_requests.map(&:check_run).map(&:deployment)

    if deployments.empty?
      deliver_error!(422, errors: "No pending deployment requests to approve or reject")
    end

    begin
      GateApprovalLog.approve_or_reject_requests(current_user, pending_gate_requests, data["state"], data["comment"])
    rescue ArgumentError => e
      deliver_error!(422, errors: e.message)
    end

    GitHub::PrefillAssociations.prefill_associations(deployments, [:creator, :repository], available_records: [repo])
    deliver :deployment_hash, deployments, repo: repo
  end

  # allows a github app to approve or reject pending `custom` gates
  post "/repositories/:repository_id/actions/runs/:run_id/deployment_protection_rule", operation_id: "actions/review-custom-gates-for-run" do
    repo = find_repo!
    deliver_error!(404) unless repo.can_use_environments_api? && current_user.is_a?(Bot)

    control_access :approve_custom_gate,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: repo.private?

    workflow_run = find_workflow_run(repo)
    data = receive_with_openapi

    pending_custom_gates = workflow_run.check_suite.pending_custom_gate_requests_by_environment_name(current_user, data["environment_name"])

    if pending_custom_gates.empty?
      deliver_error!(422, message: "No pending custom deployment requests in workflow run `#{workflow_run.id}` to approve or reject")
    end

    comment = data["comment"] || ""
    begin
      if data["state"].blank? && !data["comment"].blank?
        GateApprovalLog.post_comment_for_pending_custom_gate_requests(current_user, pending_custom_gates, comment)
      else
        GateApprovalLog.approve_or_reject_requests(current_user, pending_custom_gates, data["state"], comment)
      end
    rescue ArgumentError => e
      deliver_error!(422, message: e.message)
    end

    deliver_empty(status: 204)
  end

  private

  def find_workflow_run(repo)
    workflow_run = Actions::WorkflowRun.find_by_id(params["run_id"])
    record_or_404(workflow_run)
    deliver_error!(404) unless repo.id == workflow_run.repository_id

    workflow_run
  end
end
