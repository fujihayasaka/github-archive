# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DraftPullRequestReviewThread < Platform::Inputs::Base
      description "Specifies a review comment thread to be left with a Pull Request Review."

      argument :path, String, "Path to the file being commented on.", required: true
      argument :line, Integer, "The line of the blob to which the thread refers. The end of the line range for multi-line comments.", required: true
      argument :side, Enums::DiffSide, "The side of the diff on which the line resides. For multi-line comments, this is the side for the end of the line range.", default_value: :right, required: false
      argument :start_line, Integer, "The first line of the range to which the comment refers.", required: false
      argument :start_side, Enums::DiffSide, "The side of the diff on which the start line resides.", default_value: :right, required: false
      argument :body, String, "Body of the comment to leave.", required: true
    end
  end
end
