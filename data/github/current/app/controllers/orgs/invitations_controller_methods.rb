# typed: true
# frozen_string_literal: true

module Orgs::InvitationsControllerMethods
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { ApplicationController }

  module ClassMethods
    def limit_invitation_roles(*roles)
      @limited_invitation_roles ||= []
      @limited_invitation_roles += Array.wrap(roles.map(&:to_s))
    end

    def limited_invitation_roles
      @limited_invitation_roles || []
    end
  end

  private

  # Internal: Finds a pending invitation for the current user or from the
  # supplied invitation token.
  #
  # Returns an OrganizationInvitation or renders a response.
  def find_pending_invitation
    @pending_invitation ||= if email_invitation?
      find_pending_email_invitation
    elsif logged_in?
      find_pending_user_invitation
    end

    @pending_invitation || pending_invitation_not_found
  end
  attr_reader :pending_invitation

  def pending_invitation_not_found
    T.bind(self, T.any(
      Orgs::InvitationsController,
      Orgs::Invitations::OptOutsController,
      Orgs::Invitations::AcceptanceController,
      BillingManagersController
    ))
    if login_required_to_view_invitation?
      login_required
    elsif already_member?
      redirect_to_return_to_or_org_profile
    else
      render "orgs/invitations/not_found", status: :not_found,
        locals: { organization: this_organization }
    end
  end

  def render_sign_up_via_invitation(invitation:, invitation_token: nil, billing_manager_invite: false)
    view = create_view_model(
      Orgs::Invitations::ShowPendingPageView,
      invitation: invitation,
      invitation_token: invitation_token,
      billing_manager_invitation: billing_manager_invite
    )
    render "orgs/invitations/sign_up_via_invitation", layout: "layouts/session_authentication", locals: { view: view }
  end

  def find_pending_email_invitation
    T.bind(self, T.any(
      Orgs::InvitationsController,
      Orgs::Invitations::OptOutsController,
      Orgs::Invitations::AcceptanceController,
      BillingManagersController
    ))
    return unless email_invitation?
    this_organization.pending_invitations.
      with_business_role(*self.class.limited_invitation_roles).
      find_by_token(params[:invitation_token])
  end

  def find_pending_user_invitation
    T.bind(self, T.any(
      Orgs::InvitationsController,
      Orgs::Invitations::OptOutsController,
      Orgs::Invitations::AcceptanceController,
      BillingManagersController
    ))
    this_organization.pending_invitation_for \
      current_user,
      role: self.class.limited_invitation_roles
  end

  def email_invitation?
    params[:invitation_token].present?
  end

  def login_required_to_view_invitation?
    !logged_in? && !email_invitation?
  end

  def already_member?
    T.bind(self, T.any(
      Orgs::InvitationsController,
      Orgs::Invitations::OptOutsController,
      Orgs::Invitations::AcceptanceController,

      BillingManagersController
    ))
    this_organization.direct_or_team_member?(current_user)
  end

  def sso_required_for_joining?
    T.bind(self, T.any(
      Orgs::InvitationsController,
      Orgs::Invitations::OptOutsController,
      Orgs::Invitations::AcceptanceController,
      BillingManagersController
    ))
    this_organization.external_identity_session_owner.saml_sso_enforced? || pending_invitation.external_identity.present?
  end

  def redirect_to_return_to_or_org_profile
    T.bind(self, T.any(
      Orgs::InvitationsController,
      Orgs::Invitations::OptOutsController,
      Orgs::Invitations::AcceptanceController,
      BillingManagersController
    ))
    if params[:return_to].present?
      safe_redirect_to params[:return_to], fallback: user_path(this_organization)
    else
      redirect_to user_path(this_organization)
    end
  end

  def reinstate_return_to_path
    T.bind(self, Orgs::Controller)
    params.fetch(:return_to, user_path(this_organization))
  end
end
