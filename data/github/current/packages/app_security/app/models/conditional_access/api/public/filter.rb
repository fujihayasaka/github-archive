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

  def conditional_access_policies
    if idp_cap_for_filters_enabled?
      [
        :external_conditional_access_policy,
        :ip_allowlist,
        :legacy_personal_access_tokens,
        :personal_access_tokens,
        :saml,
        :two_factor,
        :personal_access_tokens_expiration_limit
      ]
    else
      [
        :ip_allowlist,
        :legacy_personal_access_tokens,
        :personal_access_tokens,
        :saml,
        :two_factor,
        :personal_access_tokens_expiration_limit
      ]
    end
  end

  # methods necessary to support the policies included
  def idp_cap_for_filters_enabled?
    begin
      return false unless actor.present?
      actor.feature_enabled?(:idp_cap_for_filters)
    rescue Platform::Errors::Execution
      false
    end
  end

  def anonymous?
    !callback.send(:logged_in?)
  end

  def actor
    callback.send(:current_user) || raise_missing_context!("request must provide an Actor in context")
  end

  def actor_ip
    callback.send(:ip_for_allowed_check) || raise_missing_context!("request must provide an IP address in context")
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
