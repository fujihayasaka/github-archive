# typed: true
# frozen_string_literal: true

module Api::App::UsersDependency
  extend T::Helpers
  requires_ancestor { Api::App }

  # Ensures the user actor is not blocked by another resource owner.
  #
  # user     - User actor to check.
  # owner_id - Integer ID of potentially blocking owner.
  #
  # Halts the request if the user is blocked by the given owner.
  def ensure_not_blocked!(user, owner_id)
    return false if !owner_id || !user || user.id == owner_id
    if user.blocked_by?(owner_id)
      deliver_error! 403, message: "Blocked"
    end
  end
end
