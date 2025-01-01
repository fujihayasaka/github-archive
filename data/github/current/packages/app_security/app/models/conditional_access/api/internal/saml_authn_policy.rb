# typed: true
# frozen_string_literal: true

# The SamlAuthnPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource has SAML enabled.
#
# This is the GraphQL specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Internal::SamlAuthnPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::SAML

  def saml_enforce(target)
    raise Platform::Errors::Execution.new("SAML", "saml error")
  end
end
