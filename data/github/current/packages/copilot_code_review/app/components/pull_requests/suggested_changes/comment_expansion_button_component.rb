# typed: true
# frozen_string_literal: true

module PullRequests
  module SuggestedChanges
    class CommentExpansionButtonComponent < ApplicationComponent
      MINIMUM_LINES_TO_RENDER = 20
      REACT_PARTIAL_NAME = "custom-copilot-code-review-comment"

      sig { params(comment: T.untyped).void }
      def initialize(comment:)
        @comment = comment
      end

      private

      sig { returns(T.untyped) }
      attr_reader :comment

      sig { returns(T::Boolean) }
      def render?
        return false unless comment.is_a?(PullRequestReviewComment)
        return false unless comment.copilot?
        enough_lines_to_render?
      end

      sig { returns(T::Boolean) }
      def enough_lines_to_render?
        number_of_total_lines > MINIMUM_LINES_TO_RENDER
      end

      sig { returns(Integer) }
      memoize def number_of_total_lines
        return 0 if suggestion_from_comment.nil?

        T.must(suggestion_from_comment).lines.size
      end

      sig { returns(T.nilable(String)) }
      def suggestion_from_comment
        Array.wrap(GitHub::Goomba::PRCommentSuggestionPipeline.call(comment.body)[:raw_suggestions]).first
      end
    end
  end
end
