# typed: true
# frozen_string_literal: true

class Api::ActionsDynamicWorkflows < Api::App
  include ReceiveSchemaWithOpenApi

  # Trigger a dynamic workflow run.
  post "/repositories/:repository_id/actions/dynamic", operation_id: "actions/run-dynamic-workflow" do
    repo = find_repo!

    control_access :run_dynamic_workflow,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    # Note: This endpoint is being deprecated in favor of Api::Internal::ActionsDynamicWorkflows
    if current_integration.feature_flag_enabled_or_raise?(:actions_block_public_dynamic_workflows_api) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      deliver_error! 404
    end

    data = receive_with_schema("actions-dynamic-workflow", "start")
    ref = find_ref!(repo, data["ref"])
    inputs = data["inputs"]
    workflow = data["workflow"]
    workflow_name = data["workflow_name"]
    slug = data["slug"]

    # Max inputs size
    limit = if FeatureFlag.vexi.enabled?(:actions_dynamic_workflow_api_1mb_inputs_limit, repo, default: false)
      1024 * 1024 # 1MB
    else
      MYSQL_TEXT_FIELD_LIMIT
    end

    if inputs && inputs.to_json.length > limit
      deliver_error! 422, message: "inputs are too large."
    end

    # Limit the number of inputs
    if FeatureFlag.vexi.enabled?(:actions_dynamic_workflow_api_max_10_inputs, repo, default: false)
      if inputs.is_a?(Hash) && inputs.size > 10
        deliver_error! 422, message: "too many inputs (maximum 10)."
      end
    end

    result = repo.run_dynamic_workflow(
      actor: current_user,
      workflow: workflow,
      ref: ref.qualified_name,
      inputs: inputs,
      workflow_name: workflow_name,
      slug: slug,
      integration_name: current_user.integration.slug, # assumes this will always be a bot
      entry_point: :rest_api_trigger_actions_dynamic_workflow
    )

    validate_result!(result)

    deliver :run_dynamic_workflow_hash, {
      execution_id: result.value.execution_id,
      workflow_run_id: result.value.workflow_run_id,
      repository: repo,
      workflow: workflow,
      ref: ref.qualified_name,
      workflow_name: workflow_name,
      slug: slug,
    }, status: 201
  end

  # Get information about a dynamically triggered workflow run.
  get "/repositories/:repository_id/actions/dynamic/:execution_id", operation_id: :internal do
    @route_owner = "@github/c2c-actions-experience"

    repo = find_repo!

    control_access :run_dynamic_workflow,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    check_suite = repo.actions_check_suites.includes(:workflow_run).find_by(external_id: params[:execution_id])
    record_or_404(check_suite)

    workflow_run = check_suite.workflow_run
    deliver_error!(404) unless repo.id == check_suite.repository_id && workflow_run.event == "dynamic"

    deliver :workflow_run_hash, workflow_run
  end

  private

  def find_ref!(repo, ref)
    repo_ref = repo.refs.find(ref)
    deliver_error! 422, message: "No ref found for: #{ref}" unless repo_ref

    repo_ref
  rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
    deliver_error! 422, message: "No ref found for: #{ref}"
  end

  def validate_result!(result)
    unless result
      Failbot.report(StandardError.new("no response from launch run_dynamic_workflow"))
      deliver_error! 503, message: "Run dynamic workflow service unavailable"
    end

    unless result.call_succeeded?
      if result.status == 422 && result.options.has_key?(:message)
        deliver_error! 422, message: result.options[:message]
      end

      deliver_error! 500, message: "Failed to run dynamic workflow"
    end
  end
end
