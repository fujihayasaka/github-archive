# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CommentPositionMultilineInput < Platform::Inputs::Base
      description "Specifies the range of lines a pull request review thread is being made on"

      argument :start_path, String, "File path for the first line the pull request review thread has been made on.", required: true
      argument :start_line, Integer, "The line number of the first line in the range of lines the thread is being made on", required: true
      argument :start_commit_oid, String, "Commit identifier for the first file line the review comment is being made on.", required: true
      argument :end_path, String, "The file path for the last line the thread is being made on", required: true
      argument :end_line, Integer, "Line number of the last line the review thread is being made on.", required: true
      argument :end_commit_oid, String, "Commit identifier for the last file line the review comment is being made on.", required: true
    end
  end
end
