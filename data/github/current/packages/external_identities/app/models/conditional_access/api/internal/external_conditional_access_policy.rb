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
    target = target_provider.target(resource)
    return :no if target == :no_target_for_conditional_access

    business = business_from_target(target)
    return :no unless business

    return :no unless business.feature_enabled?(:idp_cap_for_web)
    super
  end

  def external_conditional_access_policy_enforce(target)
    message = @idp_message if defined?(@idp_message) && @idp_message
    message ||= MESSAGE

    raise Platform::Errors::Execution.new("External CAP", "IdP based IP allowlist blocked: #{message}")
  end
end
