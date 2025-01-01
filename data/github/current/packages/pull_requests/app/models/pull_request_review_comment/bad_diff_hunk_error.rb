# typed: true
# frozen_string_literal: true

class PullRequestReviewComment
  class BadDiffHunkError < StandardError
    def message
      "Unable to position comment due to unexpected diff hunk format"
    end
  end
end
