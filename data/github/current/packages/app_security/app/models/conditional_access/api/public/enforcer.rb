# typed: true
# frozen_string_literal: true

# This is the public API (REST and GraphQL) specific implementation of
# ConditionalAccess::Enforcer wired up with the policies to use in production.
#
# As of today, SAML hasn't been migrated to ConditionalAccess::Enforcer
class ConditionalAccess::Api::Public::Enforcer < ConditionalAccess::Enforcer
  include ::ConditionalAccess::Api::Public::TenantVerificationPolicy
  include ::ConditionalAccess::Api::Public::EnterpriseAccessVerificationPolicy
  include ::ConditionalAccess::Api::Public::IpAllowlistPolicy
  include ::ConditionalAccess::Api::Public::TwoFactorAuthnPolicy
  include ::ConditionalAccess::Api::Public::EmuOwnershipPolicy
  include ::ConditionalAccess::Api::Public::EmuVisibilityPolicy
  include ::ConditionalAccess::Api::Public::ExternalConditionalAccessPolicy
  include ::ConditionalAccess::Api::Public::LegacyPersonalAccessTokensPolicy
  include ::ConditionalAccess::Api::Public::PersonalAccessTokensPolicy
  include ::ConditionalAccess::Api::Public::SamlAuthnPolicy
  include ::ConditionalAccess::Api::Public::PersonalAccessTokensExpirationLimitPolicy

  DEFAULT_POLICIES = [
    :emu_ownership,
    :ip_allowlist,
    :two_factor,
    :legacy_personal_access_tokens,
    :personal_access_tokens,
    :personal_access_tokens_expiration_limit,
    :external_conditional_access_policy,
  ]

  def initialize(callback)
    super(callback, do_authzd_science: true)
  end

  # Policies enabled through Conditional Access Policies framework (CAP)
  # will be enforced through enforce_conditional_access_policies method
  def conditional_access_policies
    DEFAULT_POLICIES
  end

  # Policies that are registered - may or may not
  # be included in the default policies
  def registered_policies
    [:enterprise_access_verification, :tenant_verification, :emu_visibility, :saml] + DEFAULT_POLICIES
  end

  # Policies eligible to be compared to authzd policies
  def authzd_science_policies
    [
      :enterprise_access_verification,
      :tenant_verification,
      :emu_visibility,
      :saml,
      :emu_ownership,
      :ip_allowlist,
      :two_factor,
      :legacy_personal_access_tokens,
      :personal_access_tokens,
      :external_conditional_access_policy,
    ]
  end

  def actor
    callback.send(:actor_for_conditional_access)
  end

  def true_actor
    callback.respond_to?(:actor_for_conditional_access_authzd, true) ? callback.send(:actor_for_conditional_access_authzd) : nil
  end

  def actor_ip
    callback.send(:ip_for_allowed_check)
  end

  def actor_ip_for_authzd
    (callback.respond_to?(:ip_for_allowed_check, true) && callback.send(:ip_for_allowed_check)) || GitHub.context[:actor_ip]
  end

  def action
    callback.send(:action)
  end

  def action_for_authzd
    callback.respond_to?(:action, true) ? callback.send(:action) : nil
  end

  def remote_token_auth?
    callback.send(:remote_token_auth?)
  end

  def remote_token_auth_for_authzd?
    callback.respond_to?(:remote_token_auth?, true) ? callback.send(:remote_token_auth?) : false
  end

  def repository
    callback.send(:find_repo)
  end

  def repository_for_authzd
    callback.respond_to?(:find_repo, true) ? callback.send(:find_repo) : nil
  end

  def logged_in?
    callback.send(:logged_in?)
  end

  def logged_in_for_authzd?
    callback.respond_to?(:logged_in?, true) ? callback.send(:logged_in?) : nil
  end

  def anonymous?
    !callback.send(:logged_in?)
  end

  def anonymous_for_authzd?
    !logged_in?
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

  def location
    :api
  end

  # determines if the request evaluated is safe (e.g. is a read operation like GET or HEAD)
  def safe_request_method?
    # REST: callback == Resource specific API class that inherits Api::App
    # GraphQL: callback == Platform::Authorization::PermissionCheck
    # Internal Twirp (only Package Registry): callback ==
    #   Api::Internal::TwirpPackageregistry::v1::Authorization
    callback.send(:read_request?)
  end

  def safe_request_method_for_authzd?
    callback.respond_to?(:read_request?, true) ? callback.send(:read_request?) : false
  end

  def web_session
    # Expose the web session so we can use it for the optional SAML policy.
    # As of this commit, it's called for persisted GraphQL queries and for the Copilot Twirp API.
    callback.send(:web_session) if actor.present?
  end

  def web_session_for_authzd
    callback.send(:web_session) if actor.present? && callback.respond_to?(:web_session, true)
  end

  def request_access_security_header
    if callback.respond_to?(:request, true)
      # used for api requests gets a value of a security header
      callback.request.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER]
    else
      # used for graphQL requests
      callback.request_access_security_header
    end
  end

  def request_access_security_header_for_authzd
    if callback.respond_to?(:request, true)
      # used for api requests gets a value of a security header
      callback.request.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER]
    elsif callback.respond_to?(:request_access_security_header, true)
      # used for graphQL requests
      callback.request_access_security_header
    end
  end

  def authzd_cap_actor
    callback.respond_to?(:actor_for_conditional_access_authzd, true) ? callback.send(:actor_for_conditional_access_authzd) : nil
  end

  def authzd_cap_request_attributes
    attrs = {}

    if actor_ip_for_authzd
      attrs["conditional.access.ip"] = actor_ip_for_authzd
    end

    if web_session_for_authzd
      attrs["conditional.access.web_session_id"] = web_session_for_authzd.id
    end

    if anonymous_for_authzd?
      attrs["conditional.access.anonymous"] = true
    end

    if safe_request_method_for_authzd?
      attrs["conditional.access.safe_request_method"] = true
    end

    if action_for_authzd
      attrs["conditional.access.action"] = action_for_authzd
    end

    if repository_for_authzd
      attrs["conditional.access.repository_id"] = repository_for_authzd.id
    end

    if authenticated_key_for_authzd
      attrs["conditional.access.authenticated_key_id"] = authenticated_key_for_authzd.id
    end

    if authenticated_through_integration_for_authzd?
      attrs["conditional.access.authenticated_through_integration"] = true
    end

    if request_access_security_header_for_authzd
      attrs["conditional.access.request_access_security_header"] = request_access_security_header_for_authzd
    end

    if GitHub.internal_api_role?
      attrs["conditional.access.internal_api_request"] = true
    end

    attrs
  end

  def authzd_enforcer_type
    if callback.respond_to?(:authzd_enforcer_type, true)
      # SAML access_allowed might change the enforcer type
      return callback.send(:authzd_enforcer_type) if !callback.send(:authzd_enforcer_type).nil?
    end
    "API::Public"
  end
end
