# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class PullRequestReviewItem < Platform::Unions::Base
      description "An object contained in a pull request review."

      mobile_only true

      possible_types(
        Objects::PullRequestReviewThread,
        Objects::PullRequestReviewComment,
      )
    end
  end
end
