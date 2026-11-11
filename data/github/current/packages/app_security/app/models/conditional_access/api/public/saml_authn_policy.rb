# typed: true
# frozen_string_literal: true

# The SamlAuthnPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource has SAML enabled.
#
# This is the GraphQL specific implementation, and is meant to be
# used solely in that context.
# It is an optional policy that is registered with the public enforcer.
module ConditionalAccess::Api::Public::SamlAuthnPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::SAML

  def saml_enforce(target)
    message = "SAML error"
    callback.set_forbidden_message(message)
  end
end
