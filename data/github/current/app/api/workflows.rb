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
    deliver_error! 422, message: "Actions has been disabled for this user." if current_user.spammy?

    deliver_error! 422, message: "Cannot trigger a 'workflow_dispatch' on a disabled workflow" if workflow.disabled?

    data = receive_with_schema("workflow", "dispatch")
    ref_input = data["ref"]
    ref = find_ref!(repo, ref_input)
    qualified_name = ref.qualified_name

    # Ensure ref strings are UTF-8 encoded to handle non-ASCII branch names (e.g., Japanese characters)
    # Git returns strings with ASCII-8BIT encoding which causes errors when passed to Twirp/protobuf
    if FeatureFlag.vexi.enabled?(:actions_workflow_dispatch_utf8_ref, repo, repo.owner, default: false)
      qualified_name = qualified_name.dup.force_encoding(Encoding::UTF_8) if qualified_name.encoding != Encoding::UTF_8
    end

    parsed_workflow = Actions::ParsedWorkflow.parse_from_yaml(repo, workflow.path, qualified_name)

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

    default_enabled = FeatureFlag.vexi.enabled?(:actions_workflow_dispatch_return_run_id, repo, repo.owner, default: false)
    return_run_id = changeset_active?(:change_workflow_dispatch_response_status) || default_enabled || data["return_run_details"]

    result = repo.dispatch_workflow_event(
      current_user.id,
      workflow.path,
      qualified_name,
      inputs,
      sync_flow_enabled: true,
      actor: current_user
    )

    validate_workflow_dispatch_result!(result)
    if return_run_id
      deliver :workflow_dispatch_hash, { workflow_run_id: result.value.workflow_run_id }, repo: repo, status: 200
    else
      deliver_empty(status: 204)
    end
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

  def validate_workflow_dispatch_result!(result)
    unless result
      Failbot.report(StandardError.new("no response from launch run_workflow"))
      deliver_error! 500, message: "Failed to run workflow dispatch"
    end

    unless result.call_succeeded?
      # 422 errors from Launch are user errors such as yaml issues or spammy user blocks
      if result.status == 422
        message = result.options&.dig(:message) || "Workflow dispatch failed due to invalid request"
        deliver_error! 422, message: message
      else
        deliver_error! 500, message: "Failed to run workflow dispatch"
      end
    end
  end

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
