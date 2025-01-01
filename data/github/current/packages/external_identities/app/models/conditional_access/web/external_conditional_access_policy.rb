# typed: true
# frozen_string_literal: true

# The ExternalConditionalAccessPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource satisfies the
# Identity Provider Conditional Access Policies.
# This is the Web specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Web::ExternalConditionalAccessPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::ExternalConditionalAccessPolicy

  def external_conditional_access_policy_applicable(resource:, target_provider:)
    target = target_provider.target(resource)
    return :no if target == :no_target_for_conditional_access
    business = business_from_target(target)
    return :no unless business
    return :no unless business.idp_cap_for_web_enabled?
    super
  end

  def external_conditional_access_policy_enforce(target)
    render_external_cap_forbidden_interstitial(target)
  end

  private

  ENFORCEMENT_STATUS = :forbidden

  def render_external_cap_forbidden_interstitial(target)
    idp_message = defined?(@idp_message) && @idp_message
    message = MESSAGE
    message += " IdP error message: #{idp_message}" if idp_message

    request = T.unsafe(self).callback.send(:request)
    if request.format.try(:html?) || request.format.try(:html_fragment?)
      business = business_from_target(target)
      T.unsafe(self).callback.send(
        :render,
        ConditionalAccess::ExternalConditionalAccess::AccessForbiddenComponent.new(
          target: business,
          message: idp_message
        ),
        status: ENFORCEMENT_STATUS,
        layout: "application"
      )
    elsif request.format.try(:js?) || request.format.try(:json?)
      T.unsafe(self).callback.send(
        :render,
        json: { error: message },
        status: ENFORCEMENT_STATUS
      )
    else
      T.unsafe(self).callback.send(
        :render,
        plain: message,
        status: ENFORCEMENT_STATUS
      )
    end
  end
end
