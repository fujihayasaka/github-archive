# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CommentPositionFileInput < Platform::Inputs::Base
      description "Specifies which file a pull request review thread is being made on"

      argument :path, String, "Path to the file being commented on.", required: true
      argument :commit_oid, String, "Commit identifier the review comment has been made on.", required: true
      argument :base_commit_oid, Scalars::GitObjectID, "The base commit OID of the diff for left-side positioning. If not provided, defaults to the PR's merge base.", required: false
      argument :head_commit_oid, Scalars::GitObjectID, "The head commit OID of the diff. If not provided, defaults to the PR's head commit.", required: false
    end
  end
end
