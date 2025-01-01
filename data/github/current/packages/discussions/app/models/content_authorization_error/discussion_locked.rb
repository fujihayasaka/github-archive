# typed: true
# frozen_string_literal: true

# Error indicating that the operation is not allowed based on discussion lock. e.g.
# Only someone allowed to push to the repository can comment on a locked discussion
# (unlocked discussions have no such restriction).
class ContentAuthorizationError::DiscussionLocked < ContentAuthorizationError
  sig { returns(T.untyped) }
  def symbolic_error_code
    :locked
  end

  sig { returns(T.untyped) }
  def message
    "Unable to create comment because discussion is locked."
  end

  sig { returns(T.untyped) }
  def documentation_url
    "#{GitHub.help_url}/articles/locking-conversations/"
  end
end
