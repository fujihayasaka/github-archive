# typed: true
# frozen_string_literal: true

# This is the public API (REST and GraphQL) specific implementation of
# ConditionalAccess::Filter wired up with the policies to use in production.
#
# Includes 2FA, SAML and IP-Allowlist policies
class ConditionalAccess::Api::Public::Filter < ConditionalAccess::Filter
  include ConditionalAccess::Policy::TwoFactorAuthn
  include ConditionalAccess::Policy::SAML
  include ConditionalAccess::Policy::IpAllowlist
  include ConditionalAccess::Policy::LegacyPersonalAccessTokens
  include ConditionalAccess::Policy::PersonalAccessTokens
  include ConditionalAccess::Policy::PersonalAccessTokensExpirationLimit
  include ConditionalAccess::Policy::ExternalConditionalAccessPolicy

  def initialize(callback)
    super(callback, do_authzd_science: true)
  end

  def conditional_access_policies
    [
      :external_conditional_access_policy,
      :ip_allowlist,
      :legacy_personal_access_tokens,
      :personal_access_tokens,
      :saml,
      :two_factor,
      :personal_access_tokens_expiration_limit
    ]
  end

  def authzd_science_policies
    [
      :external_conditional_access_policy,
      :ip_allowlist,
      :legacy_personal_access_tokens,
      :personal_access_tokens,
      :saml,
      :two_factor,
      :personal_access_tokens_expiration_limit,
    ]
  end

  # methods necessary to support the policies included
  def anonymous?
    !callback.send(:logged_in?)
  end

  def authzd_cap_actor
    callback.send(:current_user) || nil # do not raise on missing context - anonymous requests can legitimately have nil here
  end

  def authzd_cap_request_attributes
    attrs = {}
    if actor_ip_for_authzd
      attrs["conditional.access.ip"] = actor_ip_for_authzd
    end

    if anonymous?
      attrs["conditional.access.anonymous"] = true
    end

    attrs
  end

  def actor
    callback.send(:current_user) || raise_missing_context!("request must provide an Actor in context")
  end

  def actor_ip
    callback.send(:ip_for_allowed_check) || raise_missing_context!("request must provide an IP address in context")
  end

  def actor_ip_for_authzd
    (callback.respond_to?(:ip_for_allowed_check, true) && callback.send(:ip_for_allowed_check)) || GitHub.context[:actor_ip]
  end

  def web_session
    # API calls don't have a web session!
    nil
  end

  def location
    :api
  end

  private

  MISSING_CONTEXT_ERR = "MISSING_CONDITIONAL_ACCESS_ATTR".freeze

  def raise_missing_context!(msg)
    raise Platform::Errors::Execution.new(MISSING_CONTEXT_ERR, msg)
  end
end
