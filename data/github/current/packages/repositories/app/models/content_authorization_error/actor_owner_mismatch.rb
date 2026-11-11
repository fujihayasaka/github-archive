# typed: true
# frozen_string_literal: true

# Error indicating that that actor must match the would-be owner of the
# content being created.
class ContentAuthorizationError::ActorOwnerMismatch < ContentAuthorizationError
  def message
    "You cannot create content on someone else's behalf."
  end
end
