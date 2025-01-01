# typed: true
# frozen_string_literal: true

# The EnterpriseManagedUser policy makes sure access to resources outside the
# enterprise is unauthorized for a managed user
#
# This is the Public API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Public::EmuOwnershipPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::EmuOwnership

  # Public API specific enforcement implementation
  def emu_ownership_enforce(target)
    message = "Unauthorized: As an Enterprise Managed User, you cannot access this content"
    callback.set_forbidden_message(message)
  end

end
