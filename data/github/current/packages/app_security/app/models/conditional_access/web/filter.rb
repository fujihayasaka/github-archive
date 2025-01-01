# typed: true
# frozen_string_literal: true

# This is the ApplicationController specific implementation of ConditionalAccess::Filter
# wired up with the policies to use in production.
#
# Includes 2FA, SAML and IP-Allowlist policies
class ConditionalAccess::Web::Filter < ConditionalAccess::Filter
  include ConditionalAccess::Web::Helpers
  include ConditionalAccess::Policy::TwoFactorAuthn
  include ConditionalAccess::Policy::SAML
  include ConditionalAccess::Policy::IpAllowlist
  include ConditionalAccess::Policy::ExternalConditionalAccessPolicy

  def initialize(callback, do_authzd_science: true)
    super(callback, do_authzd_science: do_authzd_science)
  end

  def authzd_science_policies
    [:ip_allowlist]
  end

  def conditional_access_policies
    [:external_conditional_access_policy, :ip_allowlist, :saml, :two_factor]
  end

  def anonymous?
    !actor
  end

  def actor
    callback.send(:current_user) || nil
  end

  def location
    :web
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

  def authzd_cap_actor
    actor
  end
end
