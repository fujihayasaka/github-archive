# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CommentPositionLineInput < Platform::Inputs::Base
      description "Specifies which line a pull request review thread is being made on"

      argument :path, String, "Path to the file being commented on.", required: true
      argument :line, Integer, "Line number the review comment is on. The first line of a file is line one", required: true
      argument :commit_oid, String, "Commit identifier the review comment has been made on.", required: true
    end
  end
end
