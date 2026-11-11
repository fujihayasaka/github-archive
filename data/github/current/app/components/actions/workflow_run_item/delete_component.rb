# typed: true
# frozen_string_literal: true

class Actions::WorkflowRunItem::DeleteComponent < ApplicationComponent
  def initialize(current_repository:, workflow_run:, dialog_id:)
    @current_repository = current_repository
    @workflow_run = workflow_run
    @dialog_id = dialog_id
  end

  private

  def delete_run_path
    delete_workflow_run_path(
      workflow_run_id: workflow_run.id,
      user_id: current_repository.owner,
      repository: current_repository
    )
  end

  def delete_pull_requests_list_src
    workflow_run_delete_pull_requests_list_path(
      user_id: current_repository.owner,
      repository: current_repository,
      workflow_run_id: workflow_run.id
    )
  end

  attr_reader :current_repository, :workflow_run, :dialog_id
end
