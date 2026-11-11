# typed: false
# frozen_string_literal: true

module LineCommentHelper
  def create_line_comment_thread_path(thread)
    case thread
    when DeprecatedPullRequestReviewThread
      "#{pull_request_path(thread.pull)}/review_comment/create"
    when CommitCommentThread
      "/#{thread.repository.name_with_owner}/commit_comment/create"
    else
      raise TypeError, "expected thread, got #{thread.class}"
    end
  end
end
