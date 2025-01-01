# typed: true
# frozen_string_literal: true

# The EnterpriseManagedUser policy makes sure access to resources outside the
# enterprise is unauthorized for a managed user
#
# This is the Internal GraphQL API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Internal::EmuOwnershipPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }
  include ::ConditionalAccess::Policy::EmuOwnership

  def emu_ownership_enforce(target)
    raise Platform::Errors::Execution.new("EMU", "Unauthorized operation for Enterprise Managed User")
  end
end
