# typed: true
# frozen_string_literal: true
class Orgs::TeamChangeParentRequestsController < Orgs::Controller
  before_action :require_team_change_parent_request
  before_action :organization_read_required
  before_action :ensure_viewer_can_administer_requested_team, only: :approve
  before_action :ensure_viewer_can_administer_one_team, only: :cancel

  def approve # rubocop:todo GitHub/UseRestfulActions
    begin
      @team_change_parent_request.approve(actor: current_user)

      TeamChangeParentRequest.cleanup_duplicates_to(@team_change_parent_request, current_user)

      flash[:notice] = "The request was approved."
    rescue TeamChangeParentRequest::AlreadyApprovedError
      flash[:error] = "The request has already been approved"
    end

    redirect_to :back
  end

  def cancel # rubocop:todo GitHub/UseRestfulActions
    begin
      @team_change_parent_request.cancel(actor: current_user)
      flash[:notice] = "The request was cancelled."
    rescue TeamChangeParentRequest::AlreadyApprovedError
      flash[:error] = "The request has already been approved"
    end
    redirect_to :back
  end

  private

  def require_team_change_parent_request # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @team_change_parent_request ||= TeamChangeParentRequest.find(params[:id])
  end

  def ensure_viewer_can_administer_requested_team
    return if viewer_can_administer_requested_team?
    flash[:error] = "You do not have permission to approve this request."
    redirect_to :back
  end

  def ensure_viewer_can_administer_one_team
    return if viewer_can_administer_requested_team? || viewer_can_administer_requesting_team?
    flash[:error] = "You do not have permission to cancel this request."
    redirect_to :back
  end

  def viewer_can_administer_requested_team?
    @team_change_parent_request.requested_team.adminable_by?(current_user)
  end

  def viewer_can_administer_requesting_team?
    @team_change_parent_request.requesting_team.adminable_by?(current_user)
  end
end
