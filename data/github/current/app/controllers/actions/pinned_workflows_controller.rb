# typed: true
# frozen_string_literal: true

class Actions::PinnedWorkflowsController < AbstractRepositoryController
  include GitHub::Memoizer
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create, :destroy]

  before_action :find_workflow

  def create
    begin
      workflow.pin(current_user)
      if react_ui_enabled?
        respond_to do |format|
          format.html do
            flash[:notice] = "Workflow #{workflow.visible_name} pinned."
          end
          format.json do
            render json: { message: "Workflow #{workflow.visible_name} pinned." }, status: :ok
          end
        end
      else
        flash[:notice] = "Workflow #{workflow.visible_name} pinned."
      end
    rescue Actions::Workflow::AlreadyPinnedError
      respond_with_pin_error("Workflow #{workflow.visible_name} is already pinned.")
    rescue Actions::Workflow::MaxPinnedWorkflowsReachedError
      respond_with_pin_error("You can only pin up to #{Actions::PinnedWorkflow::MAXIMUM_PINNED_WORKFLOWS} workflows at a time.")
    rescue Actions::Workflow::CannotPinInactiveWorkflowError
      respond_with_pin_error("Unable to pin this workflow because it is not active.")
    rescue Actions::Workflow::UserCannotPinWorkflowError
      respond_with_pin_error("You do not have permission to pin this workflow.", status: :forbidden)
    ensure
      redirect_to :back unless performed?
    end
  end

  def destroy
    begin
      workflow.unpin(current_user)
      if react_ui_enabled?
        respond_to do |format|
          format.html do
            flash[:notice] = "Workflow #{workflow.visible_name} unpinned."
          end
          format.json do
            render json: { message: "Workflow #{workflow.visible_name} unpinned." }, status: :ok
          end
        end
      else
        flash[:notice] = "Workflow #{workflow.visible_name} unpinned."
      end
    rescue Actions::Workflow::AlreadyUnpinnedError
      respond_with_pin_error("Workflow #{workflow.visible_name} is already unpinned.")
    rescue Actions::Workflow::UserCannotPinWorkflowError
      respond_with_pin_error("You do not have permission to unpin this workflow.", status: :forbidden)
    ensure
      redirect_to :back unless performed?
    end
  end

  private

  def react_ui_enabled?
    FeatureFlag.vexi.enabled?(:actions_workflows_react_toggle, current_user, default: false)
  end

  def respond_with_pin_error(message, status: :unprocessable_entity)
    if react_ui_enabled?
      respond_to do |format|
        format.html do
          flash[:error] = message
        end
        format.json do
          render json: { error: message }, status: status
        end
      end
    else
      flash[:error] = message
    end
  end

  def find_workflow
    render_404 unless workflow
  end

  memoize def workflow
    workflow = Actions::Workflow.find_by(id: params[:workflow_id], repository: current_repository)
  end
end
