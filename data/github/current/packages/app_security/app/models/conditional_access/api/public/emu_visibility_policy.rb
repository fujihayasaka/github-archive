# typed: true
# frozen_string_literal: true

# The Enterprise Managed User Visibility policy makes sure access to resources
# inside the enterprise is unauthorized for any actor outside of the enterprise.
#
# This is the Public API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Public::EmuVisibilityPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::EmuVisibility

  # Public API specific enforcement implementation
  def emu_visibility_enforce(target)
    callback.send(:send_not_found)
  end

end
