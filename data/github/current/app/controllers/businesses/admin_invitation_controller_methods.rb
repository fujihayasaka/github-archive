# typed: true
# frozen_string_literal: true

module Businesses::AdminInvitationControllerMethods
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { Businesses::BusinessController }

  private

  def accept_pending_invitation(invitation)
    errors = []
    begin
      invitation.accept acceptor: current_user
    rescue BusinessAdministratorInvitation::AlreadyAcceptedError
      errors << "This invitation has already been accepted."
    rescue BusinessAdministratorInvitation::InvalidAcceptorError
      errors << "Viewer cannot accept an invitation when they are not the invitee."
    rescue BusinessAdministratorInvitation::AcceptorAlreadyOwnerError
      errors << "This invitation cannot be accepted by an existing enterprise owner."
    rescue Business::UserHasNoExternalIdentityError => error
      errors << error.message
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = "You are now #{invitation.role_for_message} of #{this_business.name}."
    end
  end

  def email_invitation?
    params[:invitation_token].present?
  end

  def render_pending_admin_invitation_not_found
    return render_404 unless this_business
    render "businesses/pending_admin_invitation_not_found", status: :not_found
  end

  def must_enable_two_factor?
    this_business.two_factor_requirement_enabled? &&
      !current_user.two_factor_authentication_enabled?
  end

  def ensure_saml_sso_requirement_is_met
    return if this_business.saml_sso_requirement_met_by?(current_user)
    render_external_identity_session_required(target: this_business)
  end
end
