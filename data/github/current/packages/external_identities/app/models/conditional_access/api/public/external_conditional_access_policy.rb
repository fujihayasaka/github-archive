# typed: false
# frozen_string_literal: true

# The ExternalConditionalAccessPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource satisfies the
# Identity Provider Conditional Access Policies.
# This is the API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Public::ExternalConditionalAccessPolicy
  include ::ConditionalAccess::Policy::ExternalConditionalAccessPolicy

  def external_conditional_access_policy_enforce(target)
    message = @idp_message if defined?(@idp_message) && @idp_message
    message ||= MESSAGE

    callback.set_forbidden_message(message)
  end
end
