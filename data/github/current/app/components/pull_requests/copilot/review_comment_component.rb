# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class ReviewCommentComponent < PullRequests::ReviewCommentComponent

      def feedback_path
        repo_code_review_feedback_path(pull_request.repository.owner.display_login,
          pull_request.repository.name,
          pull_request.number)
      end

      def user_feedback_options
        [
          { label: "Comment is harmful or unsafe", value: "OFFENSIVE_OR_DISCRIMINATORY" },
          { label: "Comment is poorly formatted", value: "POORLY_FORMATTED" },
          { label: "Comment is not true", value: "INCORRECT" },
          { label: "Comment is not helpful", value: "UNHELPFUL" },
          { label: "Comment is attached to the wrong line(s)", value: "INCORRECT_LINE" },
          { label: "Code suggestion is harmful or unsafe", value: "SUGGESTION_OFFENSIVE_OR_DISCRIMINATORY" },
          { label: "Code suggestion is poorly formatted", value: "SUGGESTION_POORLY_FORMATTED" },
          { label: "Code suggestion does not solve the problem in the comment", value: "SUGGESTION_UNHELPFUL" },
          { label: "Code suggestion is invalid", value: "SUGGESTION_INVALID" }
        ]
      end
    end
  end
end
