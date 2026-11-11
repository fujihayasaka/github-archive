# typed: true
# frozen_string_literal: true

# Error indicating that the ghost user cannot create content.
class ContentAuthorizationError::GhostCantDoThat < ContentAuthorizationError
  def message
    "The Ghost user can't do that."
  end
end
