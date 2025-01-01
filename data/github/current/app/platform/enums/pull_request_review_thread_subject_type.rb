# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewThreadSubjectType < Platform::Enums::Base
      description "The possible subject types of a pull request review comment."

      value "LINE", "A comment that has been made against the line of a pull request", value: "line"
      value "FILE", "A comment that has been made against the file of a pull request", value: "file"
    end
  end
end
