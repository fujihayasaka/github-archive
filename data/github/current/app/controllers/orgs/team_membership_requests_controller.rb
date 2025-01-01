# typed: true
# frozen_string_literal: true

class Orgs::TeamMembershipRequestsController < Orgs::Controller
  before_action :login_required
  before_action :this_team_required
  before_action :admin_on_team_required, only: [:approve, :deny]
  before_action :ensure_requester_is_direct_member
  before_action :sudo_filter, only: [:approve]

  def create
    if this_team.member?(current_user)
      message = "You are already a member of this team."
    elsif this_team.request_membership(current_user)
      message = (
        "Membership requested. We’ll let you know once an administrator has reviewed your request.")
    else
      message = "Sorry, something went wrong. Try again?"
    end

    redirect_with_notice(message)
  end

  def destroy
    requester = current_user
    @membership_request = find_membership_request_for(requester)
    return render_404 if @membership_request.nil?

    @membership_request.delete

    redirect_with_notice("Okay, we’ve cancelled your request to join this team.")
  end

  def approve # rubocop:todo GitHub/UseRestfulActions
    requester = User.find_by_login(params[:requester])
    @membership_request = find_membership_request_for(requester)
    return render_404 if @membership_request.nil?

    begin
      @membership_request.approve(actor: current_user)
    rescue TeamMembershipRequest::AlreadyApprovedError
      return render_404
    end

    redirect_with_notice("Membership request approved. The user has been added to the team.")
  end

  def deny # rubocop:todo GitHub/UseRestfulActions
    requester = User.find_by_login(params[:requester])
    @membership_request = find_membership_request_for(requester)
    return render_404 if @membership_request.nil?

    begin
      @membership_request.cancel(actor: current_user)
    rescue TeamMembershipRequest::AlreadyApprovedError
      return render_404
    end

    redirect_with_notice("Okay, we’ve denied that person’s request to join this team.")
  end

  private

  def redirect_with_notice(message)
    safe_redirect_to(params[:return_to].presence || team_members_path(this_team), notice: message)
  end

  def find_membership_request_for(requester)
    @membership_request = this_team
      .pending_team_membership_requests
      .where(requester_id: requester.id)
      .last
  end

  def ensure_requester_is_direct_member
    render_404 unless this_team.organization.direct_member?(current_user)
  end
end
