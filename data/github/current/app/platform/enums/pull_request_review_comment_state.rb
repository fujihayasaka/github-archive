# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewCommentState < Platform::Enums::Base
      description "The possible states of a pull request review comment."

      value "PENDING", "A comment that is part of a pending review", value: "pending"
      value "SUBMITTED", "A comment that is part of a submitted review", value: "submitted"
    end
  end
end
