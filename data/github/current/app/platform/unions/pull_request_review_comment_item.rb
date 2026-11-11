# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class PullRequestReviewCommentItem < Platform::Unions::Base
      description "An object contained in a pull request review."
      visibility :internal

      possible_types(
        Objects::PullRequestThread,
        Objects::PullRequestReviewComment,
      )
    end
  end
end
