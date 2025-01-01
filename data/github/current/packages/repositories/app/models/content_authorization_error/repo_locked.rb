# typed: true
# frozen_string_literal: true

# Error indicating that the repository is locked.
class ContentAuthorizationError::RepoLocked < ContentAuthorizationError
  def symbolic_error_code
    :maintenance
  end

  def message
    "Repository has been locked for migration."
  end
end
