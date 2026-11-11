# typed: true
# frozen_string_literal: true

# Error indicating that the operation is not allowed based on issue lock. e.g.
# Only someone allowed to push to the repository can comment on a locked issue
# (unlocked issues have no such restriction).
class ContentAuthorizationError::IssueLocked < ContentAuthorizationError
  def symbolic_error_code
    :locked
  end

  def message
    "Unable to create comment because issue is locked."
  end

  def documentation_url
    "#{GitHub.help_url}/articles/locking-conversations/"
  end
end
