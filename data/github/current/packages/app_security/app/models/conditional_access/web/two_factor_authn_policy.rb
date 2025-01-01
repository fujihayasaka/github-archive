# typed: true
# frozen_string_literal: true

# The TwoFactorAuthnPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource has 2FA enabled.
#
# This is the ApplicationController specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Web::TwoFactorAuthnPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::TwoFactorAuthn

  # application controller specific enforcement implementation that shows an interstitial to user
  # prompting them to set 2FA up
  def two_factor_enforce(target)
    render_2fa_interstitial(target)
  end

  private

  ENFORCEMENT_STATUS = :forbidden

  # This is essentially a copy of render_404.
  def render_2fa_interstitial(target)
    request = callback.send(:request)
    if request.format.try(:html_fragment?)
      callback.send(:head, ENFORCEMENT_STATUS)
    elsif request.format.try(:html?)
      callback.send(:render, "conditional_access/web/2fa", locals: { target: target }, status: ENFORCEMENT_STATUS, layout: "application")
    elsif request.format.try(:js?) || request.format.try(:json?)
      callback.send(:set_static_file_csp)
      callback.send(:render, json: { error: "Forbidden - 2FA Required" }, status: ENFORCEMENT_STATUS)
    else
      callback.send(:set_static_file_csp)
      callback.send(:render, plain: "Forbidden - 2FA Required", status: ENFORCEMENT_STATUS)
    end
    nil
  end
end
