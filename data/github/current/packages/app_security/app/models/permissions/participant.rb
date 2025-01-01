# typed: true
# frozen_string_literal: true

module Permissions
  module Participant
    extend T::Helpers

    requires_ancestor { Kernel }

    class PermissionGrantError < StandardError; end
    class PermissionTFCARequiredError < StandardError; end

    def can_be_granted_permission_over!(subject, action)
      message = <<~MSG.squish
      The can_be_granted_permission_over! method must be implemented in #{self.class}.
      This method should perform any actor specific checks that could prevent it from being
      granted permissions over the target. It should either raise `PermissionGrantError` in
      the event of a valdation failure or return nothing.

      Contact @github/authorization for more information.
    MSG
      raise NotImplementedError.new(message)
    end
  end
end
