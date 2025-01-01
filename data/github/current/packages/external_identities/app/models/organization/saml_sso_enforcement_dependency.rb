# typed: false
# frozen_string_literal: true

module Organization::SamlSsoEnforcementDependency
  extend ActiveSupport::Concern

  include SamlProviderMembers

  # Public: Is this organization configured to use SAML Single Sign-on to
  # provision its memberships?
  #
  # Returns a Boolean
  def saml_sso_enabled?
    return false unless business_plus?
    async_saml_provider.then do |provider|
      provider.present? && provider.persisted?
    end.sync
  end

  # Public: Does this organization enforce membership via a SAML identity provider?
  #
  # Returns a Boolean
  def saml_sso_enforced?
    saml_sso_enabled? && saml_provider&.enforced?
  end

  # Public: Is the given user already linked to the organization via the
  # current SAML identity provider?
  #
  # Returns a Boolean
  def saml_sso_requirement_met_by?(user)
    return true if !saml_sso_enforced?
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
    return true unless saml_sso_enforced?
    external_identity_count = ActiveRecord::Base.connected_to(role: :reading) { ExternalIdentity.by_provider(saml_provider).where(user_id: user_ids).count }
    user_ids&.any? && external_identity_count == user_ids.count
  end

  # Public: Find the object that contains the relevant SAML provider for the current
  # external identity session.
  #
  # When a business organization with a business SAML provider, the business is returned
  # When a non-business organization, self is returned
  #
  # Returns business for all organizations belonging to an enterprise managed business.
  #
  # Returns the organization or it's business owner
  def external_identity_session_owner
    return self.business if async_enterprise_managed_user_enabled?.sync
    return self.business if saml_enabled_on_business?

    self
  end

  def meets_sso_requirements?(user:)
    target = external_identity_session_owner
    case target
    when ::Organization
      target.saml_sso_requirement_met_by?(user)
    when ::Business
      target.meets_sso_requirements?(user)
    end
  end

  def meets_sso_requirements_for_users?(user_ids:)
    target = external_identity_session_owner
    case target
    when ::Organization
      target.saml_sso_requirement_met_by_users?(user_ids)
    when ::Business
      return target.saml_sso_requirement_met_by_users?(user_ids) if !target.oidc_enabled? # no change in emu saml business
      return target.external_sso_requirement_met_by_users?(user_ids) if target.oidc_enabled?
    end
  end

  # Public: Is SAML SSO enabled on the business that owns the organization?
  #
  # Returns Boolen
  def saml_enabled_on_business?
    async_business_saml_provider.sync.present?
  end

  # Public: Is SSO enabled on the business that owns the organization?
  #
  # Returns Boolean
  def sso_enabled_on_business?
    target = external_identity_session_owner
    case target
    when Business
      target.external_provider_enabled?
    else
      false
    end
  end

  # Public: is access to this Organization protected by SAML SSO?
  #
  # Returns Boolean (true if SAML is enabled for this Organization or for its parent Enterprise)
  def saml_sso_present?
    saml_sso_enabled? || sso_enabled_on_business?
  end

  # Public: is SAML SSO access enabled and enforced for this Organization?
  #   true if SAML is enabled and enforced for this Organization
  #   true if SAML is enforced for the owning Enterprise (Enterprise SAML is automatically
  #   enforced if it's enabled)
  #
  # Returns Boolean
  def saml_sso_present_enforced?
    saml_sso_enforced? || business&.external_sso_enforced?
  end
end
