# typed: false
# frozen_string_literal: true

module Business::SamlSsoDependency
  extend ActiveSupport::Concern

  include SamlProviderMembers
  include Business::ExternalProviderMembers

  # Public: Is this business configured to use SAML Single Sign-on for
  # its members?
  #
  # Returns a Boolean
  def saml_sso_enabled?
    async_saml_provider.then do |provider|
      saml_enabled = provider.present? && provider.persisted?
      if saml_enabled && GitHub.single_business_environment?
        saml_enabled = provider.scim_provisioning_state_enabled?
      end
      saml_enabled
    end.sync
  end

  # Public: Is the given user already linked to the business via the
  # current SAML identity provider?
  #
  # Returns a Boolean
  def saml_sso_requirement_met_by?(user)
    return true unless saml_sso_enabled?
    # skip GHES with SCIM (all users meet SAML sso requirement including basic auth users)
    return true if enterprise_server_scim_enabled?
    user && ExternalIdentity.linked?(
      provider: saml_provider,
      user: user,
    )
  end

  # Public: Is the given user already linked to the business via the
  # current SAML identity provider?
  #
  # Returns a Boolean
  def saml_sso_requirement_met_by_users?(user_ids)
    return true unless saml_sso_enabled?
    # skip GHES with SCIM (all users meet SAML sso requirement including basic auth users)
    return true if enterprise_server_scim_enabled?
    user_ids&.any? && ExternalIdentity.by_provider(saml_provider).where(user_id: user_ids).count == user_ids.count
  end

  # Public: Does this Enterprise Account enforce membership via a SAML identity provider?
  #
  # In GHEC, all Enterprises enforce SAML SSO if it's enabled.
  #
  # Returns a Boolean
  def saml_sso_enforced?
    saml_sso_enabled?
  end

  # Public: Expire all active ExternalIdentitySessions associated with this enterprise
  #
  # Used to force a SAML SSO workflow on users when a change is made to enable GitHub's user
  # deprovisioning settings involving SAML SSO. The reasoning here is that users may have
  # organization memberships not specified in their IdP. Because enabling user deprovisioning
  # would remove them from unauthorized organizations we need to immediately force them to
  # authenticate so we get the most up-to-date SAML assertions mapping their org memberships.
  #
  # Returns nothing of consequence
  def expire_all_enterprise_sessions!(current_user:)
    return unless saml_sso_enabled? && saml_provider.saml_deprovisioning_enabled?

    # enqueue a job to expire all active external identity sessions for the enterprise
    ExpireEnterpriseSessionsJob.perform_later(self)

    # expire current_user's external identity sessions associated with the enterprise
    external_identity = current_user.external_identities.find_by(provider: saml_provider)
    external_identity.sessions.active.update_all(expires_at: 1.minute.ago) if external_identity
  end

  # Public: Check for an enterprise to not be IdP SCIM managed.
  #
  # Returns true when business is not IdP SCIM managed
  def non_scim_managed_business?
    !scim_managed_enterprise?(self)
  end

  # Public: Checks if the business under the enterprise server was enabled for SCIM
  #
  # Returns Boolean
  def enterprise_server_scim_enabled?
    return false unless GitHub.enterprise?
    return false unless GitHub.auth.saml?

    saml_sso_enabled?
  end
end
