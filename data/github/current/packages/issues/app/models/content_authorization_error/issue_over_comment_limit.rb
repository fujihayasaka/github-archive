# typed: true
# frozen_string_literal: true

# Comment authorization error indicating that the maximum number of allowed
# comments has been exceeded for this issue.
class ContentAuthorizationError::IssueOverCommentLimit < ContentAuthorizationError
  def message
    "Commenting is disabled on issues with more than #{Issue::COMMENT_LIMIT} comments"
  end
end
