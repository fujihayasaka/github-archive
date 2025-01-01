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

  def actor
    callback.send(:actor_for_conditional_access)
  end

  def actor_ip
    callback.send(:ip_for_allowed_check)
  end

  def action
    callback.send(:action)
  end

  def remote_token_auth?
    callback.send(:remote_token_auth?)
  end

  def repository
    callback.send(:find_repo)
  end

  def logged_in?
    callback.send(:logged_in?)
  end

  def anonymous?
    !callback.send(:logged_in?)
  end

  def authenticated_key
    callback.send(:authenticated_key)
  end

  def authenticated_through_integration?
    return false if callback.send(:integration_user_request?)
    callback.send(:current_integration).present? && actor.instance_of?(Integration)
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

  def web_session
    # Expose the web session so we can use it for the optional SAML policy.
    # As of this commit, it's called for persisted GraphQL queries and for the Copilot Twirp API.
    callback.send(:web_session) if actor.present?
  end

  def request_access_security_header
    if callback.respond_to?(:request)
      # used for api requests gets a value of a security header
      callback.request.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER]
    else
      # used for graphQL requests
      callback.request_access_security_header
    end
  end
end
