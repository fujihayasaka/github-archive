# typed: true
# frozen_string_literal: true

class Orgs::Invitations::AcceptanceController < Orgs::Controller
  include Orgs::InvitationsControllerMethods
  limit_invitation_roles :admin, :direct_member, :reinstate

  before_action :login_required
  before_action :find_pending_invitation
  before_action :ensure_two_factor_requirement_is_met

  def create
    saml_session_owner = this_organization.external_identity_session_owner
    if saml_sso_required?(saml_session_owner)
      render_external_identity_session_required(target: saml_session_owner)
      return
    end

    result = pending_invitation.accept(acceptor: current_user,
                              via_email: params[:via_email].present?)

    # If accepting the invitation fails, redirect and show the error to the user.
    if result.error?
      error = result.error
      if result.status == :does_not_meet_team_requirements
        error = error + "Please contact the person who sent you this invitation."
      end

      flash[:error] = error

      if result.status == :email_not_associated_with_logged_in_user
        return redirect_to settings_email_preferences_path
      end

      return redirect_to org_show_invitation_path
    end

    if ActiveModel::Type::Boolean.new.cast(params[:copilot_seat]).present?
      with_database_error_fallback do
        member_request = MemberFeatureRequest.create(
          requester: current_user,
          request_entity: this_organization,
          feature: MemberFeatureRequest::Feature::CopilotForBusiness
        )
      end
    end

    # Users that needed to verify their email address to accept the invite
    # will have no use for this notice which will show up on their settings/emails page.
    if this_organization.org_invite_email_verification_enabled?
      ActiveRecord::Base.connected_to(role: :writing) do
        current_user.dismiss_notice("show_link_to_org_invite")
      end
    end

    flash[:notice] = case pending_invitation.role
    when "direct_member"
      "You are now a member of #{this_organization.safe_profile_name}!"
    when "admin"
      "You are now an owner of #{this_organization.safe_profile_name}!"
    end

    if params[:return_to].present?
      safe_redirect_to params[:return_to],
                      fallback: user_path(this_organization)
    elsif pending_invitation.reinstate?
      redirect_to org_reinstate_status_path
    else
      redirect_to user_path(this_organization)
    end
  end

  private

  def saml_sso_required?(saml_session_owner)
    !saml_requirement_met?(saml_session_owner) || external_identity_with_saml?(saml_session_owner)
  end

  def saml_requirement_met?(saml_session_owner)
    saml_session_owner.saml_sso_requirement_met_by?(current_user) ||
      pending_invitation.reinstating_outside_collaborator?
  end

  def external_identity_with_saml?(saml_session_owner)
    pending_invitation.external_identity.present? &&
      saml_session_owner.saml_provider.saml_provisioning_enabled?
  end

  def ensure_two_factor_requirement_is_met
    unless this_organization.two_factor_requirement_met_by?(current_user)
      redirect_to org_show_invitation_path
    end
  end
end
