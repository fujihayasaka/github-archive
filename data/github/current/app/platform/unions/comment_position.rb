# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class CommentPosition < Platform::Unions::Base
      description "The position type associated with a Pull Request comment (i.e: line, file, multiline)"
      feature_flag :graphql_pr_comment_positioning

      possible_types(
        Objects::CommentPositions::FileComment,
        Objects::CommentPositions::LineComment,
        Objects::CommentPositions::MultilineComment,
        Objects::CommentPositions::IndeterminateComment
      )

      def self.resolve_type(object, context)
        case object[:position].type
        when :file
          Objects::CommentPositions::FileComment
        when :line
          Objects::CommentPositions::LineComment
        when :multiline
          Objects::CommentPositions::MultilineComment
        when :indeterminate
          Objects::CommentPositions::IndeterminateComment
        end
      end
    end
  end
end
