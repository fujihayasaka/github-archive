# typed: true
# frozen_string_literal: true

# The EnterpriseManagedUser policy makes sure access to resources outside the
# enterprise is unauthorized for a managed user
#
# This is the ApplicationController specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Web::EmuOwnershipPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::EmuOwnership

  # application controller specific enforcement implementation
  def emu_ownership_enforce(target)
    callback.send(:render_404)
  end

end
