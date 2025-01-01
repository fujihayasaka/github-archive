# typed: true
# frozen_string_literal: true

class Actions::WorkflowNavComponent < ApplicationComponent
  include ActionsHelper

  def initialize(selected_by_ids:,
    selected_workflow:,
    workflow:,
    current_repo:,
    current_user:,
    allow_pinning: false,
    filters: {},
    **system_arguments)
    @selected_by_ids = selected_by_ids
    @selected_workflow = selected_workflow
    @system_arguments = system_arguments
    @current_repo = current_repo
    @current_user = current_user
    @workflow = workflow
    @allow_pinning = allow_pinning
    @filters = filters
    @list = system_arguments[:list] || Primer::Beta::NavList::Group.new
  end

  def before_render
    super

    return unless workflow_list_flags_enabled?
    # This class shows the trailing action button on hover only
    @system_arguments[:classes] = class_names(
      @system_arguments[:classes],
      "actions-workflow-list-item"
    )
  end

  def selected_workflow_id
    @selected_workflow&.id
  end

  def filtered_runs_path
    params = repo_params
    query = actions_filtered_query(filters: @filters)

    params[:query] = query unless query.blank?

    if workflow_filename
      params[:workflow_file_name] = workflow_filename
      params[:lab] = true if @workflow.lab?

      workflow_runs_list_path(params)
    else
      actions_path(params)
    end
  end

  def workflow_name
    @workflow.visible_name
  end

  def workflow_disabled?
    @workflow.disabled?
  end

  def workflow_list_flags_enabled?
    @current_repo.feature_enabled?(:actions_workflow_list_pinning)
  end

  def workflow_is_pinned?
    @workflow.is_pinned?
  end

  def workflow_id
    @workflow.id
  end

  def unpin_dialog_id
    "unpin-workflow-#{@workflow.id}"
  end

  def workflow_test_selector
    if @workflow.required?
      "req-workflow-rendered"
    else
      "workflow-rendered"
    end
  end

  private

  def repo_params
    {
      user_id: @current_repo.owner_display_login,
      repository: @current_repo
    }
  end

  def workflow_filename
    @workflow.filename
  end
end
