# typed: true
# frozen_string_literal: true

# This is the GraphQL specific implementation of ConditionalAccess::Enforcer
# wired up with the policies to use in production.
class ConditionalAccess::Api::Internal::Enforcer < ConditionalAccess::Enforcer
  include ::ConditionalAccess::Api::Internal::EnterpriseAccessVerificationPolicy
  include ::ConditionalAccess::Api::Internal::EmuVisibilityPolicy
  include ::ConditionalAccess::Api::Internal::TwoFactorAuthnPolicy
  include ::ConditionalAccess::Api::Internal::SamlAuthnPolicy
  include ::ConditionalAccess::Api::Internal::IpAllowlistAuthnPolicy
  include ::ConditionalAccess::Api::Internal::EmuOwnershipPolicy
  include ::ConditionalAccess::Api::Internal::LegacyPersonalAccessTokensPolicy
  include ::ConditionalAccess::Api::Internal::PersonalAccessTokensPolicy
  include ::ConditionalAccess::Api::Internal::PersonalAccessTokensExpirationLimitPolicy
  include ::ConditionalAccess::Api::Internal::ExternalConditionalAccessPolicy

  DEFAULT_POLICIES = [
    :enterprise_access_verification,
    :emu_visibility,
    :emu_ownership,
    :ip_allowlist,
    :legacy_personal_access_tokens,
    :personal_access_tokens,
    :saml,
    :two_factor,
    :personal_access_tokens_expiration_limit,
    :external_conditional_access_policy,
  ]

  attr_reader :aggregate_time

  def initialize(callback)
    @aggregate_time = 0
    super(callback, do_authzd_science: true)
  end

  def increase_agreggate_enforcement_time(amount)
    @aggregate_time += amount
  end

  # policies enabled through Conditional Access Policies framework (CAP)
  # will be enforced through enforce_conditional_access_policies method
  def conditional_access_policies
    DEFAULT_POLICIES
  end

  # Policies eligible to be compared to authzd policies
  def authzd_science_policies
    [
      :enterprise_access_verification,
      :emu_visibility,
      :emu_ownership,
      :ip_allowlist,
      :legacy_personal_access_tokens,
      :personal_access_tokens,
      :saml,
      :two_factor,
      :external_conditional_access_policy,
    ]
  end

  def authzd_cap_actor
    actor
  end

  # Policies that are registered - may or may not
  # be included in the default policies
  def registered_policies
    DEFAULT_POLICIES
  end

  def actor
    raise_invalid_origin!
    callback[:viewer]
  end

  def actor_ip
    raise_invalid_origin!
    remote_ip!
  end

  def actor_ip_for_authzd
    actor_ip || GitHub.context[:actor_ip]
  end

  def repository
    nil
  end

  def web_session
    raise_invalid_origin!

    # not all internal requests have a session. Some can be done via PAT for example:
    # https://github.com/github/github/blob/4fd2e934c22106338a04c1d2b889179a12f14f46/test/integration/commits_controller_test.rb#L323-L329
    callback[:user_session] if actor.present?
  end

  def web_session_for_authzd
    web_session
  end

  def anonymous?
    raise_invalid_origin!
    actor.blank?
  end

  def anonymous_for_authzd?
    anonymous?
  end

  # determines if the request evaluated is safe (e.g. is a read operation like GET or HEAD)
  #
  # For Internal GraphQL API, the callback will be GraphQL::Query::Context
  def safe_request_method?
    raise_invalid_origin!
    query!
  end

  def safe_request_method_for_authzd?
    safe_request_method?
  end

  def location
    :internal_api
  end

  def authenticated_key
    callback.send(:authenticated_key)
  end

  def authenticated_key_for_authzd
    callback.respond_to?(:authenticated_key, true) ? callback.send(:authenticated_key) : nil
  end

  def authenticated_through_integration?
    return false if callback.nil?
    return false unless callback.respond_to?(:integration_user_request?) && callback.respond_to?(:current_integration)
    return false if callback.send(:integration_user_request?)
    callback.send(:current_integration).present? && actor.instance_of?(Integration)
  end

  def authenticated_through_integration_for_authzd?
    authenticated_through_integration?
  end

  private

  def query!
    @graph_query_present ||= callback.respond_to?(:query)
    unless @graph_query_present
      raise Platform::Errors::Execution.new("MISSING_GRAPHQL_QUERY", "Internal GraphQL call without query in context")
    end
    callback.query.query?
  end

  def raise_invalid_origin!
    @internal_origin ||= (callback[:origin] == Platform::ORIGIN_INTERNAL)
    unless @internal_origin
      raise Platform::Errors::Execution.new(
        "INVALID_REQUEST_ORIGIN",
        "#{self.class.name} must be called from an internal origin only, but received origin: #{callback[:origin]}"
      )
    end
  end

  def remote_ip!
    @remote_ip ||= callback[:rails_request]&.remote_ip
    unless @remote_ip
      raise Platform::Errors::Execution.new(
        "MISSING_ACTOR_IP",
        "actor ip was missing in GraphQL context"
      )
    end
    @remote_ip
  end

  def request_access_security_header
    # used for graphQL requests on Query::Context
    callback[:request_access_security_header]
  end

  def request_access_security_header_for_authzd
    request_access_security_header
  end

  def authzd_cap_request_attributes
    attrs = {}

    if actor_ip_for_authzd
      attrs["conditional.access.ip"] = actor_ip_for_authzd
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

    if web_session_for_authzd
      attrs["conditional.access.web_session_id"] = web_session_for_authzd.id
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
    "API::Internal"
  end
end
