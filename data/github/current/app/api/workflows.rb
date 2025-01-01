# typed: true
# frozen_string_literal: true

class Api::Workflows < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::ActionsWorkflowsHelper

  # Get all non required workflows for a repository.
  get "/repositories/:repository_id/actions/workflows", operation_id: "actions/list-repo-workflows" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workflows = workflows(repo)

    deliver :workflows_hash, { workflows: workflows, total_count: workflows.total_entries }
  end

  # Get a non-required workflow.
  get "/repositories/:repository_id/actions/workflows/:workflow_id", operation_id: "actions/get-workflow" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workflow = find_workflow!(repo)
    deliver :workflow_hash, workflow
  end

  # Get the billable information for a non-required workflow
  get "/repositories/:repository_id/actions/workflows/:workflow_id/timing", operation_id: "actions/get-workflow-usage" do
    deliver_error!(404) if GitHub.enterprise?

    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workflow = find_workflow!(repo)
    payload = billing_payload_for_workflow(workflow, repo)

    deliver_raw(payload)
  end

  # Trigger a workflow_dispatch event on non-required workflow
  post "/repositories/:repository_id/actions/workflows/:workflow_id/dispatches", operation_id: "actions/create-workflow-dispatch" do
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    workflow = find_workflow!(repo)

    deliver_error! 422, message: "Actions has been disabled for this user." if current_user.action_invocation_blocked?
    deliver_error! 422, message: "Actions has been disabled for this repository." if repo.action_invocation_blocked?

    deliver_error! 422, message: "Cannot trigger a 'workflow_dispatch' on a disabled workflow" if workflow.disabled?

    data = receive_with_schema("workflow", "dispatch")
    ref = find_ref!(repo, data["ref"])

    parsed_workflow = Actions::ParsedWorkflow.parse_from_yaml(repo, workflow.path, ref.qualified_name)

    deliver_error! 422, message: "Workflow does not have 'workflow_dispatch' trigger" unless parsed_workflow&.has_workflow_dispatch_trigger?

    provided_inputs = data["inputs"]
    if provided_inputs && provided_inputs.to_json.length > MYSQL_TEXT_FIELD_LIMIT
      deliver_error! 422, message: "inputs are too large."
    end

    begin
      inputs = parsed_workflow.process_inputs(provided_inputs)
    rescue ArgumentError => e
      deliver_error! 422, message: e.message
    end

    repo.dispatch_workflow_event(
      current_user.id,
      workflow.path,
      ref.qualified_name,
      inputs
    )

    deliver_empty(status: 204)
  end

  # Enable a non-required workflow
  put "/repositories/:repository_id/actions/workflows/:workflow_id/enable", operation_id: "actions/enable-workflow" do
    @route_owner = "@github/c2c-actions-experience"
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    workflow = find_workflow!(repo)
    begin
      workflow.enable(current_user)
      deliver_empty(status: 204)
    rescue Actions::Workflow::CannotBeEnabledError
      deliver_error!(403, message: "Unable to enable a workflow that is not active.")
    end
  end

  # Disable a non-required workflow
  put "/repositories/:repository_id/actions/workflows/:workflow_id/disable", operation_id: "actions/disable-workflow" do
    @route_owner = "@github/c2c-actions-experience"
    repo = find_repo!

    control_access :write_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    workflow = find_workflow!(repo)
    deliver_error!(422, message: "Unable to disable this workflow.") unless workflow.disableable?
    begin
      workflow.disable(current_user)
      deliver_empty(status: 204)
    rescue Actions::Workflow::NotActiveError
      deliver_error!(403, message: "Unable to disable a workflow that is not active.")
    end
  end

  private

  def find_ref!(repo, ref)
    repo_ref = repo.refs.find(ref)
    deliver_error! 422, message: "No ref found for: #{ref}" unless repo_ref

    repo_ref
  rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
    deliver_error! 422, message: "No ref found for: #{ref}"
  end

  def find_workflow!(repo)
    workflow = repo.workflows.non_required.find_from_id_or_filename(params[:workflow_id])

    deliver_error!(404) unless workflow

    if !current_user&.site_admin? && workflow.spammy?
      unless current_user&.spammy? && workflow.workflow_runs.any? { |wf_run| wf_run.actor_id == current_user&.id }
        deliver_error!(404)
      end
    end

    workflow
  end
end
