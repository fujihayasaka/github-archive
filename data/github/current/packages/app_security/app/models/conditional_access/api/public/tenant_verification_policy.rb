# typed: true
# frozen_string_literal: true

# The Tenant Verification policy makes sure access to proxima stamps have a valid tenant and that
# actors are either site admins or match the tenant of the current request.
# This is the Public API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Public::TenantVerificationPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::TenantVerification

  # Public API specific enforcement implementation
  def tenant_verification_enforce(target)
    callback.send(:send_not_found)
  end
end
