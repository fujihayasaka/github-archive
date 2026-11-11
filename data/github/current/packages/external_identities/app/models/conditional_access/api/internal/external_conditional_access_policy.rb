# typed: true
# frozen_string_literal: true

# The ExternalConditionalAccessPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource satisfies the
# Identity Provider Conditional Access Policies.
#
# This is the GraphQL specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Internal::ExternalConditionalAccessPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::ExternalConditionalAccessPolicy

  def external_conditional_access_policy_applicable(resource:, target_provider:)
    ConditionalAccess::AuthzdRollout.authzd_cap_debug_logging("external_conditional_access_policy",
      "starting external cap policy",
      details: { location: "internal_api" },
      resource: resource)
    target = target_provider.target(resource)
    return :no if target == :no_target_for_conditional_access
    ConditionalAccess::AuthzdRollout.authzd_cap_debug_logging("external_conditional_access_policy",
      "target found",
      details: { location: "internal_api" },
      resource: resource,
      target: target)

    business = business_from_target(target)
    return :no unless business
    ConditionalAccess::AuthzdRollout.authzd_cap_debug_logging("external_conditional_access_policy",
      "business found",
      details: { location: "internal_api" },
      resource: resource,
      target: target)

    enabled = business.idp_cap_for_web_enabled?
    ConditionalAccess::AuthzdRollout.authzd_cap_debug_logging("external_conditional_access_policy",
      "idp_cap_for_web_enabled? result",
      details: { location: "internal_api", idp_cap_for_web_enabled: enabled },
      resource: resource,
      target: target)
    return :no unless enabled

    super
  end

  def external_conditional_access_policy_enforce(target)
    message = @idp_message if defined?(@idp_message) && @idp_message
    message ||= MESSAGE

    raise Platform::Errors::Execution.new("External CAP", "IdP based IP allowlist blocked: #{message}")
  end
end
