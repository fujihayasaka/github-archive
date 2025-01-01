# typed: true
# frozen_string_literal: true

# This is the GitAuth specific implementation of ConditionalAccess::Enforcer
# wired up with the policies to use in production.
#
# As of today, SAML hasn't been migrated to ConditionalAccess::Enforcer
class ConditionalAccess::CapGitAuth::Enforcer < ConditionalAccess::Enforcer
  include ::ConditionalAccess::CapGitAuth::IpAllowlistPolicy
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

  def initialize(callback)
    super(callback, do_authzd_science: true)
  end

  # Policies enabled through Conditional Access Policies framework (CAP)
  # will be enforced through enforce_conditional_access_policies method
  def conditional_access_policies
    DEFAULT_POLICIES
  end

  def policies_plus_saml_and_oap
    # note(bencoomes) - matches `reposdGitauthPolicyGroup` in authzd
    conditional_access_policies + [:oauth_application, :saml]
  end

  # Policies eligible to be compared to authzd policies
  def authzd_science_policies
    [
      :enterprise_access_verification,
      :emu_ownership,
      :ip_allowlist,
      :two_factor,
      :legacy_personal_access_tokens,
      :personal_access_tokens,
      :external_conditional_access_policy,
      :personal_access_tokens_expiration_limit,
      :saml,
      :oauth_application,
    ]
  end

  # Policies that are registered - may or may not
  # be included in the default policies
  def registered_policies
    [:saml, :oauth_application] + conditional_access_policies
  end

  # GitAuth specific implementation to support the included policies
  def actor
    callback.send(:user)
  end

  def actor_ip
    callback.send(:ip)
  end

  def actor_ip_for_authzd
    (callback.respond_to?(:ip, true) && callback.send(:ip)) || GitHub.context[:actor_ip]
  end

  def action
    callback.send(:action)
  end

  def action_for_authzd
    callback.respond_to?(:action, true) ? callback.send(:action) : nil
  end

  # application controller specific implementation to support the included policies
  def anonymous?
    callback.send(:anonymous?, actor)
  end

  def anonymous_for_authzd?
    callback.respond_to?(:anonymous?, true) ? callback.send(:anonymous?, actor) : false
  end

  def repository
    callback.send(:repository)
  end

  def repository_for_authzd
    callback.respond_to?(:repository, true) ? callback.send(:repository) : nil
  end

  def location
    :git_auth
  end

  def safe_request_method?
    callback.send(:action) == :read
  end

  def safe_request_method_for_authzd?
    callback.respond_to?(:action, true) ? callback.send(:action) == :read : false
  end

  def authenticated_key
    callback.send(:authenticated_key)
  end

  def authenticated_key_for_authzd
    callback.respond_to?(:authenticated_key, true) ? callback.send(:authenticated_key) : nil
  end

  def authenticated_through_integration?
    return false if callback.send(:integration_user_request?)
    callback.send(:current_integration).present? && actor.instance_of?(Integration)
  end

  def authenticated_through_integration_for_authzd?
    return false if callback.respond_to?(:integration_user_request?, true) && callback.send(:integration_user_request?)
    callback.respond_to?(:current_integration, true) && callback.send(:current_integration).present? && actor.instance_of?(Integration)
  end

  def request_access_security_header
    # used for api requests gets a value of a security header
    callback.send(:request_access_security_header) if callback.respond_to?(:request_access_security_header)
  end

  def request_access_security_header_for_authzd
    # used for api requests gets a value of a security header
    callback.respond_to?(:request_access_security_header, true) ? callback.send(:request_access_security_header) : nil
  end

  def authzd_cap_actor
    if callback.respond_to?(:public_key)
      key = callback.send(:public_key)
      return key if !key.nil?
    end
    callback.respond_to?(:user, true) ? callback.send(:user) : nil
  end

  def authzd_enforcer_type
    "GitAuth"
  end

  def authzd_cap_request_attributes
    attrs = {}

    if actor_ip_for_authzd
      attrs["conditional.access.ip"] = actor_ip_for_authzd
    end

    if action_for_authzd
      attrs["conditional.access.action"] = action_for_authzd
    end

    if repository_for_authzd
      attrs["conditional.access.repository_id"] = repository_for_authzd.id
    end

    if anonymous_for_authzd?
      attrs["conditional.access.anonymous"] = true
    end

    if authenticated_key_for_authzd
      attrs["conditional.access.authenticated_key_id"] = authenticated_key_for_authzd.id
    end

    if authenticated_through_integration_for_authzd?
      attrs["conditional.access.authenticated_through_integration"] = true
    end

    if safe_request_method_for_authzd?
      attrs["conditional.access.safe_request_method"] = true
    end

    if request_access_security_header_for_authzd
      attrs["conditional.access.request_access_security_header"] = request_access_security_header_for_authzd
    end

    if GitHub.internal_api_role?
      attrs["conditional.access.internal_api_request"] = true
    end

    if T.unsafe(self).callback.respond_to?(:public_key) && T.unsafe(self).callback.send(:public_key)
      attrs["conditional.access.public_key_id"] = T.unsafe(self).callback.send(:public_key).id
    end

    attrs
  end
end
