# typed: true
# frozen_string_literal: true

class Actions::ManualController < AbstractRepositoryController
  include FeatureFlagHelper
  include ::ActionsControllerMethods
  include ::ActionsHelper

  before_action :require_push_access, except: [:manual_run_partial]
  before_action :actions_enabled_for_repo?
  before_action :should_show_selected_workflow_run?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::IamAbilities,
    only: [:manual_run_partial]

  def manual_run_partial # rubocop:todo GitHub/UseRestfulActions
    return head :bad_request unless workflow_path.present?
    return head :not_found unless workflow.present?

    render_form
  end

  def trigger # rubocop:todo GitHub/UseRestfulActions
    return head :bad_request unless workflow_path.present?
    return head :bad_request unless ref.present?

    # Check that the workflow exists in the given ref
    return head :not_found unless parsed_workflow.present?

    # Check that the workflow record exists in the database
    return head :not_found unless workflow.present?
    return head :bad_request if workflow.disabled?

    return head :bad_request unless parsed_workflow.has_workflow_dispatch_trigger?

    if inputs && inputs.to_json.length > MYSQL_TEXT_FIELD_LIMIT
      return redirect_to redirect_path(workflow), flash: { error: "Provided inputs are too large." }
    end

    begin
      input_values = parsed_workflow.process_inputs(inputs)
    rescue ArgumentError
      return head :bad_request
    end

    # Check if we should use the synchronous Twirp flow for UI (repo or org level)
    sync_flow_enabled = FeatureFlag.vexi.enabled?(:actions_synchronous_workflow_dispatch_ui_flow, current_repository, current_repository.owner, default: false)

    # Pass workflow source as UI in order to enable creation of failure check suites on parse errors
    workflow_source = if sync_flow_enabled && FeatureFlag.vexi.enabled?(:actions_workflow_dispatch_ui_source, current_repository, current_repository.owner, default: false)
      GitHub::Launch::Services::Deploy::RunWorkflowSource::RUN_WORKFLOW_SOURCE_UI
    end

    # Trigger event to run the workflow
    result = current_repository.dispatch_workflow_event(
      current_user.id,
      workflow_path,
      ref_qualified_name,
      input_values,
      sync_flow_enabled: sync_flow_enabled,
      actor: current_user,
      source: workflow_source,
    )

    redirect_to_run_page = FeatureFlag.vexi.enabled?(:actions_workflow_dispatch_redirect_to_run_page, current_repository, current_repository.owner, default: false)

    # Complete onboarding task if applicable (before any redirect)
    if params[:show_workflow_tip].presence && current_repository.organization
      OnboardingTasks::Organizations::RunCi.new(taskable: current_repository.organization, user: current_user).complete
    end

    if sync_flow_enabled && (result.nil? || !result.call_succeeded?)
      twirp_status = result&.status || "unknown"
      GitHub.dogstats.increment(
        "actions.manual_trigger.queue",
        tags: [
          "status:failure",
          "twirp_status:#{twirp_status}",
        ]
      )
      GitHub.logger.warn(
        "actions.manual_trigger.queue_failure",
        repo_id: current_repository.id,
        workflow: workflow_path,
        ref: ref,
        twirp_status: twirp_status,
      )
      show_parse_errors = FeatureFlag.vexi.enabled?(:actions_surface_workflow_dispatch_ui_parse_errors, current_repository, current_repository.owner, default: false)
      error_msg = result&.options&.dig(:message)
      flash_text = if show_parse_errors && result&.status == 422
        "Failed to queue workflow run: #{error_msg}"
      else
        "Failed to queue workflow run. Please try again."
      end
      return redirect_to redirect_path(workflow), flash: { error: flash_text }
    # Redirect to workflow run page if feature flag enabled and result available
    elsif redirect_to_run_page && result && result.call_succeeded?
      GitHub.dogstats.increment("actions.manual_trigger.queue", tags: ["status:success"])
      return redirect_to workflow_run_path(user_id: current_repository.owner, repository: current_repository, workflow_run_id: result.value.workflow_run_id)
    end

    GitHub.dogstats.increment("actions.manual_trigger.queue", tags: ["status:success"])
    # Workflow run was queued
    redirect_to redirect_path(workflow), flash: { notice: "Workflow run was successfully requested." }
  end

  private

  def redirect_path(workflow)
    filtered_runs_by_file_path(filters: {}, filename: workflow.filename, lab: workflow.lab?, show_workflow_tip: params[:show_workflow_tip].presence)
  end

  def workflow_path
    params[:workflow]
  end

  def branch
    params[:branch] || current_repository.default_branch
  end

  def tag
    params[:tag]
  end

  def ref
    tag || branch
  end

  def ref_type
    return :tag if tag.present?

    :branch
  end

  def ref_qualified_name
    return "refs/tags/#{tag}" if tag.present?

    "refs/heads/#{branch}"
  end

  def inputs
    params[:inputs]
  end

  def workflow # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @workflow ||= current_repository.workflows.find_by(path: workflow_path)
  end

  def parsed_workflow # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @parsed_workflow ||= Actions::ParsedWorkflow.parse_from_yaml(current_repository, workflow_path, ref_qualified_name)
  end

  def workflow_inputs
    parsed_workflow&.workflow_dispatch_inputs
  end

  def render_form
    render partial: "actions/manual/manual_run_partial", locals: {
      workflow: workflow,
      workflow_in_branch: parsed_workflow&.has_workflow_dispatch_trigger?,
      selected_ref: ref,
      selected_ref_type: ref_type,
      inputs: workflow_inputs,
    }
  end

  def require_push_access
    render_404 unless current_user_can_push?
  end

  def route_supports_advisory_workspaces?
    parent_repository_can_have_actions_on_private_forks? || super
  end
end
