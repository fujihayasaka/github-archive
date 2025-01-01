# typed: true
# frozen_string_literal: true

# This is the GitAuth specific implementation of ConditionalAccess::Enforcer
# wired up with the policies to use in production.
#
# As of today, SAML hasn't been migrated to ConditionalAccess::Enforcer
class ConditionalAccess::GitAuth::Enforcer < ConditionalAccess::Enforcer
  include ::ConditionalAccess::GitAuth::IpAllowlistPolicy
  include ::ConditionalAccess::Policy::TwoFactorAuthn
  include ::ConditionalAccess::Policy::EnterpriseAccessVerification
  include ::ConditionalAccess::Policy::EmuOwnership
  include ::ConditionalAccess::Policy::ExternalConditionalAccessPolicy
  include ::ConditionalAccess::Policy::LegacyPersonalAccessTokens
  include ::ConditionalAccess::Policy::PersonalAccessTokens
  include ::ConditionalAccess::Policy::PersonalAccessTokensExpirationLimit

  DEFAULT_POLICIES = [
    :enterprise_access_verification,
    :emu_ownership,
    :ip_allowlist,
    :two_factor,
    :legacy_personal_access_tokens,
    :personal_access_tokens,
    :external_conditional_access_policy,
    :personal_access_tokens_expiration_limit,
  ]

  # Policies enabled through Conditional Access Policies framework (CAP)
  # will be enforced through enforce_conditional_access_policies method
  def conditional_access_policies
    DEFAULT_POLICIES
  end

  # Policies that are registered - may or may not
  # be included in the default policies
  def registered_policies
    conditional_access_policies
  end

  # GitAuth specific implementation to support the included policies
  def actor
    callback.send(:user)
  end

  def actor_ip
    callback.send(:ip)
  end

  def action
    callback.send(:action)
  end

  # application controller specific implementation to support the included policies
  def anonymous?
    callback.send(:anonymous?, actor)
  end

  def repository
    callback.send(:repository)
  end

  def location
    :git_auth
  end

  def safe_request_method?
    callback.send(:action) == :read
  end

  def authenticated_key
    callback.send(:authenticated_key)
  end

  def authenticated_through_integration?
    return false if callback.send(:integration_user_request?)
    callback.send(:current_integration).present? && actor.instance_of?(Integration)
  end

  def request_access_security_header
    # used for api requests gets a value of a security header
    callback.send(:request_access_security_header) if callback.respond_to?(:request_access_security_header)
  end
end
