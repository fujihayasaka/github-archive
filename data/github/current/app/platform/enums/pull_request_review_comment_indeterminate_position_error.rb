# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewCommentIndeterminatePositionError < Platform::Enums::Base
      description "Details about inability to determine positioning for a pull request review comment"

      # Missing Data
      value "MISSING_POSITIONAL_DATA", "The pull request comment is missing required positional data.", value: :missing_positional_data

      # Path Resolution Failures
      value "CANNOT_RESOLVE_PATH", "The file path could not be resolved in the commit range.", value: :cannot_resolve_path
      value "CANNOT_RESOLVE_START_PATH", "The start file path could not be resolved.", value: :cannot_resolve_start_path
      value "CANNOT_RESOLVE_END_PATH", "The end file path could not be resolved.", value: :cannot_resolve_end_path

      # Line Resolution Failures
      value "CANNOT_RESOLVE_LINE", "The line number could not be resolved.", value: :cannot_resolve_line
      value "CANNOT_RESOLVE_START_LINE", "The start line number could not be resolved.", value: :cannot_resolve_start_line
      value "CANNOT_RESOLVE_END_LINE", "The end line number could not be resolved.", value: :cannot_resolve_end_line

      # Position Resolution Failures
      value "CANNOT_RESOLVE_POSITION", "The diff position could not be resolved.", value: :cannot_resolve_position
      value "CANNOT_RESOLVE_START_POSITION", "The start diff position could not be resolved.", value: :cannot_resolve_start_position

      # Diff Resolution Failures
      value "CANNOT_RESOLVE_COMMITS", "The commit identifiers, commit range, or diff data could not be resolved.", value: :cannot_resolve_commits

      # Size Limits
      value "BLOB_CONTENTS_TOO_LARGE", "The file or diff contents are too large to process.", value: :blob_contents_too_large

      # Repositioning Failures
      value "CANNOT_REPOSITION_LINE", "The line could not be repositioned to the new commit range.", value: :cannot_reposition_line

      # Unknown Errors
      value "UNKNOWN", "An unknown error occurred while determining position.", value: :unknown
    end
  end
end
