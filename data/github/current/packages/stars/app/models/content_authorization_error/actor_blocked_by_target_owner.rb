# typed: true
# frozen_string_literal: true

# Error indicating that that actor is blocked by the content owner
class ContentAuthorizationError::ActorBlockedByTargetOwner < ContentAuthorizationError
  def message
    "You can't perform that action at this time."
  end
end
