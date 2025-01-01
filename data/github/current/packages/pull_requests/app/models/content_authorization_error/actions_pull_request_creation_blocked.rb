# typed: true
# frozen_string_literal: true

class ContentAuthorizationError::ActionsPullRequestCreationBlocked < ContentAuthorizationError
  def message
    "GitHub Actions is not permitted to create or approve pull requests."
  end
end
