# typed: true
# frozen_string_literal: true

# Error indicating that issues and issue commenting are not allowed because
# the repo has disabled issues.
class ContentAuthorizationError::IssuesDisabled < ContentAuthorizationError
  def message
    "Issues are disabled for this repo."
  end

  def http_error_code
    410
  end

  def documentation_url
    "/v3/issues/"
  end
end
