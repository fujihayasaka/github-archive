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
    if GitHub.flipper[:idp_cap_for_filters].enabled?
      [:external_conditional_access_policy, :ip_allowlist, :saml, :two_factor]
    else
      [:ip_allowlist, :saml, :two_factor]
    end
  end

  def location
    :web
  end
end
