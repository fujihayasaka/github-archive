# typed: true
# frozen_string_literal: true

# Error indicating that the repository is archived.
class ContentAuthorizationError::RepoArchived < ContentAuthorizationError
  def symbolic_error_code
    :archived
  end

  def message
    "Repository was archived so is read-only."
  end
end
