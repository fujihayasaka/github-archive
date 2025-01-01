# typed: true
# frozen_string_literal: true

# The TwoFactorAuthnPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource has 2FA enabled.
#
# This is the GraphQL specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Internal::TwoFactorAuthnPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::TwoFactorAuthn

  def two_factor_enforce(target)
    raise Platform::Errors::Execution.new("2FA", "2FA required for #{target}")
  end
end
