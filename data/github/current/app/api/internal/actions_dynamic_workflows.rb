# typed: strict
# frozen_string_literal: true

class Api::Internal::ActionsDynamicWorkflows < Api::Internal
  include ReceiveSchemaWithOpenApi

  sig { returns(T::Boolean) }
  def externally_accessible?
    # This API should not be accessible from outside the GitHub network
    # to prevent users from running dynamic workflows with tokens from
    # allowed GitHub Apps
    # https://github.com/github/sweagentd/issues/1120
    false
  end

  sig { returns(T::Boolean) }
  def require_request_hmac?
    # HMAC key name is derived from the class name
    # Set in GitHub.api_internal_actions_dynamic_workflows_hmac_keys
    # which reads "API_INTERNAL_ACTIONS_DYNAMIC_WORKFLOWS_HMAC_KEYS" environment variable
    # This should be stored in the Launch vault and federated to clients that need it
    true
  end

  sig { returns(T::Boolean) }
  def authenticated_for_private_mode?
    true
  end

  # Trigger a dynamic workflow run
  post "/internal/repositories/:repository_id/actions/dynamic", operation_id: "actions/run-dynamic-workflow-internal" do
    repo = find_repo!

    control_access :run_dynamic_workflow,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    data = receive_with_schema("actions-dynamic-workflow", "start")
    ref = find_ref!(repo, data["ref"])
    inputs = data["inputs"]
    workflow = data["workflow"]
    workflow_name = data["workflow_name"]
    slug = data["slug"]
    prevent_reruns = data["prevent_reruns"] || false

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
      prevent_reruns:,
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

  private

  sig { params(repo: Repository, ref: String).returns(Git::Ref) }
  def find_ref!(repo, ref)
    if FeatureFlag.vexi.enabled?(:actions_dynamic_workflow_api_extended_refs, repo, default: false)
      if ref.start_with?("refs/pull/")
        repo_ref = repo.extended_refs.find(ref)
      else
        repo_ref = repo.heads.find(ref)
      end
    else
      repo_ref = repo.refs.find(ref)
    end
    deliver_error! 422, message: "No ref found for: #{ref}" unless repo_ref

    repo_ref
  rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
    deliver_error! 422, message: "No ref found for: #{ref}"
  end

  sig { params(result: T.nilable(TwirpResponse)).void }
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
