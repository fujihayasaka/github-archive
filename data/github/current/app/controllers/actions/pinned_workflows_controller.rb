# typed: true
# frozen_string_literal: true

class Actions::PinnedWorkflowsController < AbstractRepositoryController
  include GitHub::Memoizer

  before_action :find_workflow

  def create
    begin
      workflow.pin(current_user)
      flash[:notice] = "Workflow #{workflow.visible_name} pinned."
    rescue Actions::Workflow::AlreadyPinnedError
      flash[:error] = "Workflow #{workflow.visible_name} is already pinned."
    rescue Actions::Workflow::MaxPinnedWorkflowsReachedError
      flash[:error] = "You can only pin up to #{Actions::PinnedWorkflow::MAXIMUM_PINNED_WORKFLOWS} workflows at a time."
    rescue Actions::Workflow::CannotPinInactiveWorkflowError
      flash[:error] = "Unable to pin this workflow because it is not active."
    rescue Actions::Workflow::UserCannotPinWorkflowError
      flash[:error] = "You do not have permission to pin this workflow."
    ensure
      redirect_to :back
    end
  end

  def destroy
    begin
      workflow.unpin(current_user)
      flash[:notice] = "Workflow #{workflow.visible_name} unpinned."
    rescue Actions::Workflow::AlreadyUnpinnedError
      flash[:error] = "Workflow #{workflow.visible_name} is already unpinned."
    rescue Actions::Workflow::UserCannotPinWorkflowError
      flash[:error] = "You do not have permission to unpin this workflow."
    ensure
      redirect_to :back
    end
  end

  private

  def find_workflow
    render_404 unless workflow
  end

  memoize def workflow
    workflow = Actions::Workflow.find_by(id: params[:workflow_id], repository: current_repository)
  end
end
