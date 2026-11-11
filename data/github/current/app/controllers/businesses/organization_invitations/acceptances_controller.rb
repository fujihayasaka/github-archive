# typed: true
# frozen_string_literal: true

class Businesses::OrganizationInvitations::AcceptancesController < Businesses::BusinessController
  before_action :business_organization_invitations_required
  before_action :login_required
  before_action :require_not_accepted_organization_invitation
  before_action :require_can_accept_organization_invitation
  before_action :non_idp_managed_business_required
  before_action :business_not_downgraded_to_free_plan_required

  def create
    errors = []
    begin
      if params[:business_owned].blank?
        errors << "Please accept the transfer to #{this_business.name}."
      else
        pending_organization_invitation.accept(current_user)
      end
    rescue BusinessOrganizationInvitation::ExpiredError
      errors << "This invitation has expired."
    rescue BusinessOrganizationInvitation::InvalidActorError
      errors << "#{current_user.display_login} cannot accept invitations on behalf of #{current_organization.display_login}."
    rescue BusinessOrganizationInvitation::InvalidInviterError
      errors << "Please contact #{this_business.name}'s account representative to invite organizations."
    rescue BusinessOrganizationInvitation::AlreadyAcceptedError
      errors << "This invitation has already been accepted."
    rescue BusinessOrganizationInvitation::CanceledError
      errors << "This invitation has been canceled."
    rescue BusinessOrganizationInvitation::AlreadyBusinessMemberError
      errors << "#{current_organization.display_login} is already part of an enterprise."
    rescue BusinessOrganizationInvitation::InsufficientAvailableLicensesError
      errors << "#{this_business.name} does not have sufficient licenses to add #{current_organization.display_login}."
    rescue BusinessOrganizationInvitation::OrganizationUpgradeToBusinessInProgressError
      errors << "#{current_organization.display_login} is currently in the process of being upgraded to enterprise."
    rescue BusinessOrganizationInvitation::OrganizationHasOutstandingBalanceError
      errors << "#{current_organization.display_login} invitation cannot be accepted because of an outstanding balance."
    rescue BusinessOrganizationInvitation::OrganizationIsInDunningError
      errors << "#{current_organization.display_login} invitation cannot be accepted because it is overdue for payment."
    rescue BusinessOrganizationInvitation::BusinessIsTradeRestrictedError
      errors << "#{current_organization.display_login} invitation cannot be accepted because there's a problem with #{this_business.name}'s payment information."
    rescue BusinessOrganizationInvitation::OrganizationIsTradeRestrictedError
      errors << "#{current_organization.display_login} invitation cannot be accepted because there's a problem with the payment information."
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = "You have accepted the invitation for #{current_organization.display_login} to join #{this_business.name}. Once it is confirmed by an enterprise owner, the organization will be transferred to #{this_business.name}."
      BusinessMailer.invited_organization_accepted(pending_organization_invitation, current_user).deliver_later
    end

    redirect_to settings_org_billing_tab_path(current_organization, tab: "payment_information")
  end

  private

  def require_can_accept_organization_invitation
    return if current_organization.adminable_by?(current_user)

    flash[:error] = "#{current_user.display_login} does not have the ability to accept invitations on behalf of #{current_organization.display_login}."
    redirect_to enterprise_organizations_path(this_business)
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
