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
    qualified_ref_name = ref.qualified_name

    # Ensure ref strings are UTF-8 encoded to handle non-ASCII branch names (e.g., Japanese characters)
    # Git returns strings with ASCII-8BIT encoding which causes errors when passed to Twirp/protobuf
    qualified_ref_name = qualified_ref_name.dup.force_encoding(Encoding::UTF_8) if qualified_ref_name.encoding != Encoding::UTF_8

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

    actor = current_user
    integration_name = current_user.integration.slug

    # Support actor override for third-party agents (only Copilot can use this)
    actor_id = data["actor_id"]
    if actor_id.present?
      # Only Copilot can use actor override
      copilot_agent = AgenticApp::CopilotAgent.instance
      unless current_user.bot? && current_user.integration&.id == copilot_agent.integration&.id
        deliver_error! 403, message: "Actor override is only allowed for Copilot."
      end

      actor = User.find_by(id: actor_id)
      deliver_error! 422, message: "Actor must be a bot." unless actor&.bot?
      bot_actor = T.cast(actor, Bot)

      agentic_app = AgenticApp.agent_for_bot_id(bot_actor.id)
      deliver_error! 422, message: "Actor must be an agentic app." unless agentic_app
      # Use current_user (the real caller — Copilot's bot) as viewer so that
      # AgenticApp::Base#restricted_by_policies? does NOT hit the `viewer.id == bot_id`
      # self-exemption short-circuit and actually evaluates enterprise opt-in / license checks.
      deliver_error! 403, message: "Agentic app is not enabled for this repository." unless agentic_app.enabled_for_repository?(repo, current_user)

      # For 3P agents: integration_name = "agents", slug derived from actor's app
      # Path becomes: dynamic/agents/{actor_app_slug}
      integration_name = "agents"
      slug = T.must(bot_actor.integration).slug
    end

    result = repo.run_dynamic_workflow(
      actor: actor,
      workflow: workflow,
      ref: qualified_ref_name,
      inputs: inputs,
      workflow_name: workflow_name,
      slug: slug,
      prevent_reruns: prevent_reruns,
      integration_name: integration_name,
      entry_point: :rest_api_trigger_actions_dynamic_workflow
    )

    validate_result!(result)

    deliver :run_dynamic_workflow_hash, {
      execution_id: result.value.execution_id,
      workflow_run_id: result.value.workflow_run_id,
      repository: repo,
      workflow: workflow,
      ref: qualified_ref_name,
      workflow_name: workflow_name,
      slug: slug,
    }, status: 201
  end

  private

  sig { params(repo: Repository, ref: String).returns(Git::Ref) }
  def find_ref!(repo, ref)
    if ref.start_with?("refs/pull/")
      repo_ref = repo.extended_refs.find(ref)
    else
      repo_ref = repo.heads.find(ref)
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
