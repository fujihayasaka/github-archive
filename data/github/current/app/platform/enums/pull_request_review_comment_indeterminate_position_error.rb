# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewCommentIndeterminatePositionError < Platform::Enums::Base
      description "Details about inability to determine positioning for a pull request review comment"

      value "OUTDATED_REVIEW_THREAD", "The pull request review thread is outdated.", value: :outdated
      value "FILE_BASE_PATH_NOT_FOUND", "The pull request comment is on a file that does not exist in the base repository.", value: :base_path_not_found
      value "FILE_HEAD_PATH_NOT_FOUND", "The pull request comment is on a file that does not exist in the base repository.", value: :head_path_not_found
      # FIXME: This is a translation for `line_requires_end_line_number` error
      # Better wording needed!
      value "LINE_COMMENT_END_LINE_NOT_FOUND", "The pull request line comment is missing an end line", value: :end_line_not_found
      value "MULTILINE_COMMENT_START_LINE_NOT_FOUND", "The pull request multiline comment is missing a start line", value: :start_line_not_found
    end
  end
end
