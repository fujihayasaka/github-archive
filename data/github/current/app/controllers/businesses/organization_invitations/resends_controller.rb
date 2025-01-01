# typed: true
# frozen_string_literal: true

class Businesses::OrganizationInvitations::ResendsController < Businesses::BusinessController
  before_action :business_organization_invitations_required
  before_action :login_required
  before_action :business_owner_required
  before_action :require_current_organization
  before_action :require_not_accepted_organization_invitation
  before_action :non_idp_managed_business_required
  before_action :business_not_downgraded_to_free_plan_required

  def create
    BusinessMailer.invited_organization(pending_organization_invitation).deliver_later

    flash[:notice] = "Invitation resent to #{pending_organization_invitation.invitee.display_login}."
    redirect_to pending_organizations_enterprise_path(this_business)
  end

  private

  def require_current_organization
    return if current_organization.present?

    flash[:error] = "Could not find organization with login: #{params[:organization_login]}"
    redirect_to :back
  end

  def require_not_accepted_organization_invitation
    return pending_organization_invitation_not_found if pending_organization_invitation.nil?
    return if !pending_organization_invitation.accepted?

    flash[:error] = "The invitation for #{current_organization.display_login} to join #{this_business.name} has already been accepted."
    redirect_to enterprise_organizations_path(this_business)
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
