# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DraftPullRequestReviewThread < Platform::Inputs::Base
      description "Specifies a review comment thread to be left with a Pull Request Review."

      # TODO: Deprecation notices.
      # Legacy positional inputs.
      argument :path, String, "Path to the file being commented on. Required if not using positioning.", required: false
      argument :line, Integer, "The line of the blob to which the thread refers. The end of the line range for multi-line comments. Required if not using positioning.", required: false
      argument :side, Enums::DiffSide, "The side of the diff on which the line resides. For multi-line comments, this is the side for the end of the line range.", default_value: :right, required: false
      argument :start_line, Integer, "The first line of the range to which the comment refers.", required: false
      argument :start_side, Enums::DiffSide, "The side of the diff on which the start line resides.", default_value: :right, required: false

      # New positional arguments
      with_options(feature_flag: :graphql_pr_comment_positioning, required: false) do
        argument :file_positioning, Inputs::CommentPositionFileInput, "Positioning data for a comment made on an entire file"
        argument :line_positioning, Inputs::CommentPositionLineInput, "Positioning data for a comment made on a specific line of a file"
        argument :multiline_positioning, Inputs::CommentPositionMultilineInput, "Positioning data for a comment made on a range of lines within a file"
      end

      argument :body, String, "Body of the comment to leave.", required: true
    end
  end
end
