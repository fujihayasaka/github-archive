# typed: true
# frozen_string_literal: true

class Businesses::OrganizationInvitations::CancellationsController < Businesses::BusinessController
  before_action :business_organization_invitations_required
  before_action :login_required
  before_action :require_pending_organization_invitation
  before_action :require_can_cancel_organization_invitation
  before_action :non_idp_managed_business_required
  before_action :business_not_downgraded_to_free_plan_required

  def create
    errors = []
    begin
      pending_organization_invitation.cancel(current_user, params[:initiated_from])
    rescue BusinessOrganizationInvitation::ExpiredError
      errors << "This invitation has expired."
    rescue BusinessOrganizationInvitation::InvalidActorError
      errors << "#{current_user.display_login} cannot cancel invitations on behalf of #{pending_organization_invitation.invitee.display_login}."
    rescue BusinessOrganizationInvitation::AlreadyConfirmedError
      errors << "This invitation has already been confirmed."
    rescue BusinessOrganizationInvitation::CanceledError
      errors << "This invitation has already been canceled."
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = "You have declined the invitation for #{current_organization.display_login} to join #{this_business.name}."
      BusinessMailer.invited_organization_rejected(pending_organization_invitation, current_user).deliver_later unless this_business.owner?(current_user)
    end

    if params[:return_to_business]
      redirect_to pending_organizations_enterprise_path(this_business)
    else
      redirect_to settings_org_billing_tab_path(current_organization, tab: "payment_information")
    end
  end

  private

  def require_can_cancel_organization_invitation
    return if current_organization.adminable_by?(current_user)
    return if this_business.owner?(current_user)

    flash[:error] = "#{current_user.display_login} does not have the ability to cancel invitations on behalf of #{current_organization.display_login}."
    if params[:return_to_business]
      redirect_to pending_organizations_enterprise_path(this_business)
    else
      redirect_to user_path(current_organization)
    end
  end

  def require_pending_organization_invitation
    pending_organization_invitation || pending_organization_invitation_not_found
  end

  memoize def pending_organization_invitation
    this_business.pending_organization_invitation_for(current_organization)
  end

  def pending_organization_invitation_not_found
    return render_404 unless this_business
    render "businesses/organization_invitations/not_found", status: :not_found
  end

  def current_organization
    return unless params[:organization_login]
    @org ||= Organization.find_by(login: params.require(:organization_login))
  end
end
