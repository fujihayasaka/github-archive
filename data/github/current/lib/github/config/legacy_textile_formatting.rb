# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module LegacyTextileFormatting
      attr_accessor :max_textile_commit_comment_id
      attr_accessor :max_textile_gist_comment_id
      attr_accessor :max_textile_issue_id
      attr_accessor :max_textile_issue_comment_id
      attr_accessor :max_textile_milestone_id
      attr_accessor :max_textile_pull_request_review_comment_id
    end
  end

  extend Config::LegacyTextileFormatting
end
