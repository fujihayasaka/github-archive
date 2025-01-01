# typed: true
# frozen_string_literal: true

# The Enterprise Managed User Visibility policy makes sure access to resources
# inside the enterprise is unauthorized for any actor outside of the enterprise.
#
# This is the Internal API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Internal::EmuVisibilityPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::EmuVisibility

  # Public API specific enforcement implementation
  def emu_visibility_enforce(target)
    raise Platform::Errors::Execution.new("EMU visibility", "Unauthorized operation for a user accessing Enterprise Managed User")
  end

end
