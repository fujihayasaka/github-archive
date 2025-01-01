# typed: true
# frozen_string_literal: true

class Businesses::OrganizationInvitationsController < Businesses::BusinessController
  before_action :business_organization_invitations_required
  before_action :login_required
  before_action :business_owner_required, only: [
    :index, :new, :suggestions, :create, :confirm_pending, :resend_pending
  ]
  before_action :sudo_filter, only: [:create]
  before_action :require_current_organization, only: [:create, :resend_pending]
  before_action :require_not_accepted_organization_invitation, only: [:accept_pending, :resend_pending]
  before_action :require_pending_organization_invitation, only: [:confirm_pending, :cancel_pending]
  before_action :require_can_accept_organization_invitation, only: [:accept_pending]
  before_action :require_can_cancel_organization_invitation, only: [:cancel_pending]
  before_action :non_idp_managed_business_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:suggestions, :new, :index],
    optional: true

  def index
    created_invitations = this_business
      .organization_invitations
      .with_status(:created)
      .reorder("business_organization_invitations.created_at asc")
    accepted_invitations = this_business
      .organization_invitations
      .with_status(:accepted)
      .reorder("business_organization_invitations.created_at asc")

    render "businesses/organizations/pending_organizations", locals: {
      created_invitations: created_invitations,
      accepted_invitations: accepted_invitations,
    }
  end

  def new
    render "businesses/organization_invitations/new"
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    headers["Cache-Control"] = "no-cache, no-store"

    respond_to do |format|
      view = create_view_model(Businesses::OrganizationInvitations::SuggestionsView,
        orgs_only: true, business: this_business, query: params[:q])
      format.html_fragment do
        render partial: "businesses/organization_invitations/suggestions",
          formats: :html,
          locals: { view: view }
      end
      format.html do
        render partial: "businesses/organization_invitations/suggestions",
          locals: { view: view }
      end
    end
  end

  def create
    begin
      invitation = BusinessOrganizationInvitation.create! \
        business: this_business, inviter: current_user, invitee: current_organization
    rescue ActiveRecord::RecordInvalid => error
      flash[:error] = error.record.errors.full_messages.first
      return redirect_to :back
    end

    if this_business.upgrade_initiated_from_organization == current_organization
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.del(this_business.org_attachment_failure_notice_key(current_user))
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end

    flash[:notice] = <<~NOTICE.squish
      You've invited #{current_organization.display_login} organization to join #{this_business.name}!
      The organization's administrators will be receiving an email shortly.
      You can check the pending tab to manage the invitation.
    NOTICE
    redirect_to pending_organizations_enterprise_path(this_business)
  end

  def accept_pending # rubocop:todo GitHub/UseRestfulActions
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
    rescue BusinessOrganizationInvitation::InsufficientAvailableSeatsError
      errors << "#{this_business.name} does not have sufficient seats to add #{current_organization.display_login}."
    rescue BusinessOrganizationInvitation::OrganizationUpgradeToBusinessInProgressError
      errors << "#{current_organization.display_login} is currently in the process of being upgraded to enterprise."
    rescue BusinessOrganizationInvitation::OrganizationHasOutstandingBalanceError
      errors << "#{current_organization.display_login} invitation cannot be accepted because of an outstanding balance."
    rescue BusinessOrganizationInvitation::OrganizationIsInDunningError
      errors << "#{current_organization.display_login} invitation cannot be accepted because it is overdue for payment."
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = "You have accepted the invitation for #{current_organization.display_login} to join #{this_business.name}. Once it is confirmed by an enterprise owner, the organization will be transferred to #{this_business.name}."
      BusinessMailer.invited_organization_accepted(pending_organization_invitation, current_user).deliver_later
    end

    redirect_to settings_org_billing_path(current_organization)
  end

  def cancel_pending # rubocop:todo GitHub/UseRestfulActions
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
      redirect_to settings_org_billing_path(current_organization)
    end
  end

  def confirm_pending # rubocop:todo GitHub/UseRestfulActions
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

  def resend_pending # rubocop:todo GitHub/UseRestfulActions
    BusinessMailer.invited_organization(pending_organization_invitation).deliver_later

    flash[:notice] = "Invitation resent to #{pending_organization_invitation.invitee.display_login}."
    redirect_to pending_organizations_enterprise_path(this_business)
  end

  private

  def business_organization_invitations_required
    return if GitHub.business_organization_invitations_available?
    render_404
  end

  def require_current_organization
    return if current_organization.present?

    flash[:error] = "Could not find organization with login: #{params[:organization_login]}"
    redirect_to :back
  end

  def require_can_accept_organization_invitation
    return if current_organization.adminable_by?(current_user)

    flash[:error] = "#{current_user.display_login} does not have the ability to accept invitations on behalf of #{current_organization.display_login}."
    redirect_to enterprise_organizations_path(this_business)
  end

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

  def require_not_accepted_organization_invitation
    return pending_organization_invitation_not_found if pending_organization_invitation.nil?
    return if !pending_organization_invitation.accepted?

    flash[:error] = "The invitation for #{current_organization.display_login} to join #{this_business.name} has already been accepted."
    redirect_to enterprise_organizations_path(this_business)
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
