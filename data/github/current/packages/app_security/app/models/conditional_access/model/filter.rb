# typed: true
# frozen_string_literal: true

# This is the ApplicationRecord specific implementation of ConditionalAccess::Filter
# wired up with the policies to use in production.
#
# Using this class in new callsites is discouraged. Callsites within ApplicationRecord should get ConditionalAccess::Web::Filter injected
# instead of creating their own instance out of the various objects needed to perform the authorization decision (e.g. UserSession)
#
# Includes 2FA, SAML and IP-Allowlist policies
class ConditionalAccess::Model::Filter < ConditionalAccess::Filter
  include ConditionalAccess::Policy::TwoFactorAuthn
  include ConditionalAccess::Policy::SAML
  include ConditionalAccess::Policy::IpAllowlist
  include ConditionalAccess::Policy::ExternalConditionalAccessPolicy

  def initialize(callback, web_session: nil, actor: nil, remote_ip: nil, location:)
    @web_session = web_session
    @actor = actor
    @remote_ip = remote_ip
    @location = location
    super(callback, do_authzd_science: true)
  end

  def conditional_access_policies
    [
      :external_conditional_access_policy,
      :ip_allowlist,
      :saml,
      :two_factor
    ]
  end

  def authzd_science_policies
    [
      :external_conditional_access_policy,
      :ip_allowlist,
      :saml,
      :two_factor,
    ]
  end

  # methods necessary to support the policies included
  def anonymous?
    !actor
  end

  def web_session
    @web_session
  end

  def web_session_for_authzd
    @web_session
  end

  def actor
    @actor
  end

  def actor_ip
    @remote_ip
  end

  def location
    @location
  end

  def authzd_cap_request_attributes
    attrs = {}

    if actor_ip_for_authzd
      attrs["conditional.access.ip"] = actor_ip_for_authzd
    end

    if anonymous?
      attrs["conditional.access.anonymous"] = true
    end

    if web_session_for_authzd
      attrs["conditional.access.web_session_id"] = web_session_for_authzd.id
    end

    attrs
  end

  def authzd_cap_actor
    actor
  end

  def actor_ip_for_authzd
    actor_ip || GitHub.context[:actor_ip]
  end
end
