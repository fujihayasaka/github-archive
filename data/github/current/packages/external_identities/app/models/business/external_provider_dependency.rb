# typed: false
# frozen_string_literal: true

# Tracking external Identity Provider dependencies for a business. Supports both SAML and OIDC
module Business::ExternalProviderDependency
  extend ActiveSupport::Concern

  include Business::ExternalProviderMembers

  # Public: Is this business configured to use SAML Single Sign-on or Open ID Connect for
  # its members?
  #
  # Returns a Boolean
  # If the provider is disabled and the customer is testing saml/oidc settings without saving
  def external_provider_enabled?
    saml_sso_enabled? || oidc_enabled?
  end

  # Public: External Identity provider configured for this business
  #
  # Returns a Boolean
  def external_provider
    saml_provider || oidc_provider
  end

  def async_external_provider
    if oidc_enabled?
      async_oidc_provider
    else
      async_saml_provider
    end
  end

  def oidc_enabled?
    return false if GitHub.single_business_environment?
    async_oidc_provider.then do |provider|
      provider.present? && provider.persisted?
    end.sync
  end

  # Public: Is the given user already linked to the business via the
  # current external identity provider?
  #
  # Returns a Boolean
  def external_sso_requirement_met_by?(user)
    return true unless external_provider_enabled?
    # skip GHES with SCIM
    return true if enterprise_server_scim_enabled?
    user && ExternalIdentity.linked?(
      provider: external_provider,
      user: user
    )
  end

  # Public: Is the given user already linked to the business via the
  # current external identity provider?
  #
  # Returns a Boolean
  def external_sso_requirement_met_by_users?(user_ids)
    return true unless external_provider_enabled?
    # skip GHES with SCIM
    return true if enterprise_server_scim_enabled?
    user_ids&.any? && ExternalIdentity.by_provider(external_provider).where(user_id: user_ids).count == user_ids.count
  end

  # Public: Does this Enterprise Account enforce membership via a SAML identity provider?
  #
  # In GHEC, all Enterprises enforce SAML SSO if it's enabled.
  #
  # Returns a Boolean
  def external_sso_enforced?
    saml_sso_enforced? || oidc_enabled?
  end

  # Public: Find the object that contains the relevant external identity provider for the current
  # external identity session.
  #
  # Returns self
  def external_identity_session_owner
    self
  end
end
