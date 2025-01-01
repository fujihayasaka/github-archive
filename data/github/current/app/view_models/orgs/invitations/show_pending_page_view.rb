# typed: true
# frozen_string_literal: true

class Orgs::Invitations::ShowPendingPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :invitation, :invitation_token, :current_external_identity_session, :billing_manager_invitation
  delegate :organization, :inviter, to: :invitation

  def logout_url
    GitHub.auth.logout_url
  end

  def two_factor_auth_disclosure_url
    "#{GitHub.help_url}/articles/securing-your-account-with-two-factor-authentication-2fa"
  end

  def audit_log_disclosure_url
    "#{GitHub.help_url}/articles/reviewing-the-audit-log-for-your-organization/#search-based-on-the-action-performed"
  end

  def invitation_disclosure_article_url
    "#{GitHub.help_url}/articles/permission-levels-for-an-organization"
  end

  def two_factor_auth_settings_permit_joining?
    organization.two_factor_requirement_met_by?(current_user)
  end

  def learn_more_url
    "#{GitHub.url}/features/copilot/"
  end

  def return_to_invitation_link(invitation_token)
    if billing_manager_invitation
      urls.org_show_pending_billing_manager_invitation_path(
        organization,
        invitation_token: invitation_token, via_email: invitation.email? ? 1 : nil
      )
    else
      urls.org_show_invitation_path(
        organization,
        invitation_token: invitation_token, via_email: invitation.email? ? 1 : nil
      )
    end
  end

  def sso_required_for_joining?
    # If SAML is enabled on the parent Enterprise, and provisioning is turned on, force user
    # through SSO regardless, so the IdP can validate the invitation. If SAML Provisioning is
    # enabled on the Enterprise, then the SAML assertion we'll receive during SSO will include
    # a `groups` attribute with a list of organizations this user is authorized to be a member
    # of. If this organization isn't in the authorized list, the invitation will be
    # automatically cancelled.
    return true if organization.sso_enabled_on_business? &&
      organization.business.saml_provider.saml_provisioning_enabled?
    return false unless organization.external_identity_session_owner.saml_sso_enforced? ||
      invitation.external_identity.present?
    return false if invitation.reinstating_outside_collaborator?
    # if a valid external identity session was provided, don't force user to SSO
    # a second time
    current_external_identity_session.nil?
  end

  # Identify whether the organization is the billing entity rather than a parent business
  #
  # The purpose of the check is to determine if a Copilot Business request option should display to invitees receiving an organization invitation
  # We [currently] allow the request Copilot checkbox component in invitations from standalone & enterprise-owned Organizations
  # Also, previously ensure that invitee has verified email and enabled SSO for joining
  # Return true if: - GitHub instance is not on Enterprise Server
  #                 - User is not an EMU Account
  #                 - User does not have free access to Copilot
  #                 - User would not get free access to Copilot if they were to apply
  #                 - User does not already have Copilot Business or Copilot Enterprise from the same or different org
  #
  # Returns a Boolean
  def display_copilot_business_seat_request?
    return false if GitHub.enterprise?
    return false if current_user.is_enterprise_managed?

    copilot_user = Copilot::User.new(current_user)
    return false if copilot_user.has_free_access? || copilot_user.can_signup_for_free?

    return false if (copilot_user.has_copilot_enterprise_access? || copilot_user.copilot_for_business_enabled?) && current_user.feature_enabled?(:hide_request_user_has_cfb_or_cfe)

    true
  end

  def idm_saml_initiate_url
    if organization.business&.saml_sso_enabled?
      urls.idm_saml_initiate_enterprise_path(organization.business, invitation_token: invitation_token)
    else
      urls.org_idm_saml_initiate_path(organization, invitation_token: invitation_token)
    end
  end
end
