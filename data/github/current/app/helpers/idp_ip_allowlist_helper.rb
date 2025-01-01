# typed: true
# frozen_string_literal: true

require "oidc/cap_validator"

module IdpIpAllowlistHelper
  NO_REFRESH_TOKEN_MESSAGE = "No refresh token available. Please single sign-on to your enterprise again."
  IDP_CAP_NOT_SATISFIED_MESSAGE = "Enabling an Identity Provider based IP allow list would prevent you from accessing the account from your current IP address. Please contact your Identity Provider administrator for assistance."

  # Will enabling the IdP IP allowlist lock out the actor?
  # Checks that the passed ip and actor combination satisfies the IdP conditional access policy.
  #
  # business - The business to enable the IdP IP allowlist for
  # actor - The actor to check satisfies the IdP conditional access policy
  # ip - The ip to check satisfies the IdP conditional access policy
  #
  # Returns [Boolean, String] - true if the actor will be locked out, false otherwise. The second value is an error message if the actor will be locked out.
  def enabling_idp_ip_allowlist_will_lock_out_actor?(business:, actor:, ip:)
    external_identity = actor.external_identities.first
    refresh_token = external_identity&.external_identity_refresh_token&.encrypted_refresh_token

    unless refresh_token
      return true, NO_REFRESH_TOKEN_MESSAGE
    end

    message = OIDC::CapValidator.satisfies_idp_web_cap?(business: business, refresh_token: refresh_token, client_ip: ip, external_identity: external_identity)

    unless message == :yes
      return true, IDP_CAP_NOT_SATISFIED_MESSAGE
    end

    false
  end
end
