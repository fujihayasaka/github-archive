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

  def conditional_access_policies
    if idp_cap_for_filters_enabled?
      [:external_conditional_access_policy, :ip_allowlist, :saml, :two_factor]
    else
      [:ip_allowlist, :saml, :two_factor]
    end
  end

  def idp_cap_for_filters_enabled?
    return false unless actor.present?
    actor.feature_enabled?(:idp_cap_for_filters)
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
end
