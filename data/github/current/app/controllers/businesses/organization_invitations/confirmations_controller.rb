# typed: true
# frozen_string_literal: true

class Businesses::OrganizationInvitations::ConfirmationsController < Businesses::BusinessController
  before_action :business_organization_invitations_required
  before_action :login_required
  before_action :business_owner_required
  before_action :require_pending_organization_invitation
  before_action :non_idp_managed_business_required
  before_action :business_not_downgraded_to_free_plan_required

  def create
    errors = []
    begin
      pending_organization_invitation.confirm(current_user)
    rescue BusinessOrganizationInvitation::ExpiredError
      errors << "This invitation has expired."
    rescue BusinessOrganizationInvitation::AlreadyConfirmedError
      errors << "This invitation has already been confirmed."
    rescue BusinessOrganizationInvitation::CanceledError
      errors << "This invitation has been canceled."
    rescue BusinessOrganizationInvitation::NotYetAcceptedError
      errors << "This invitation has not yet been accepted."
    rescue BusinessOrganizationInvitation::AlreadyBusinessMemberError
      errors << "#{current_organization.display_login} is already part of an enterprise."
    rescue BusinessOrganizationInvitation::InvalidActorError
      errors << "#{current_user.display_login} cannot confirm this invitation on behalf of #{this_business.name}."
    rescue BusinessOrganizationInvitation::InvalidInviterError
      errors << "Please contact #{this_business.name}'s account representative to invite organizations."
    rescue BusinessOrganizationInvitation::BusinessIsSpammyError
      errors << "This enterprise has been flagged and cannot confirm organization invitations."
    rescue BusinessOrganizationInvitation::OrganizationUpgradeToBusinessInProgressError
      errors << "#{current_organization.display_login} is currently in the process of being upgraded to enterprise."
    rescue BusinessOrganizationInvitation::OrganizationHasOutstandingBalanceError
      errors << "#{current_organization.display_login} invitation cannot be confirmed because of an outstanding balance."
    rescue BusinessOrganizationInvitation::OrganizationIsInDunningError
      errors << "#{current_organization.display_login} invitation cannot be confirmed because it is overdue for payment."
    rescue BusinessOrganizationInvitation::InsufficientAvailableSeatsError
      errors << "#{current_organization.display_login} invitation cannot be confirmed because the enterprise has insufficient seats."
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = <<~NOTICE.squish
        #{current_organization.display_login} has been added to #{this_business.name}.
        The organization's ownership and billing have been transferred to this
        enterprise account.
      NOTICE
      BusinessMailer.invited_organization_finalized(pending_organization_invitation, current_user).deliver_later
    end
    redirect_to enterprise_organizations_path(this_business)
  end

  private

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
