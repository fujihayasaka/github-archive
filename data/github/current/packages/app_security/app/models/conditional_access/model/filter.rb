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
    super(callback)
  end

  def conditional_access_policies
    if idp_cap_for_filters_enabled?(@actor)
      [:external_conditional_access_policy, :ip_allowlist, :saml, :two_factor]
    else
      [:ip_allowlist, :saml, :two_factor]
    end
  end

  # methods necessary to support the policies included

  def idp_cap_for_filters_enabled?(actor)
    return false unless actor.present?
    actor.feature_enabled?(:idp_cap_for_filters)
  end

  def anonymous?
    !actor
  end

  def web_session
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
end
