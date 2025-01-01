# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class CommentedIssue < Conduit::StratocasterEventAdapter
      ISSUE_COMMENT_MAX_LENGTH = 150

      def html_url = comment_url

      def title
        T.bind(self, T.untyped)
        description
      end

      def partial_path = "events/issue_comment"

      def number = issue.number

      def issue_title
        T.bind(self, T.untyped)
        issue.title
      end

      def issue_text
        T.bind(self, T.untyped)
        "#{repo_nwo}##{number}"
      end

      def url
        comment_url || issue_url
      end

      def comment_body
        T.bind(self, T.untyped)
        issue_comment.body
      end

      def formatted_comment
        T.bind(self, T.untyped)
        HTMLTruncator.new(comment_body, ISSUE_COMMENT_MAX_LENGTH).to_html(wrap: false)
      end

      def icon = "issues_comment"

      private

      def issue_comment
        T.bind(self, T.untyped)
        subject
      end

      def issue
        T.bind(self, T.untyped)
        issue_comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      def repo
        T.bind(self, T.untyped)
        issue_comment.repository
      end

      def repo_nwo
        T.bind(self, T.untyped)
        repo.name_with_display_owner
      end

      def comment_url
        issue_comment.permalink
      end

      def issue_url
        issue.permalink
      end

      def is_pull_request
        T.bind(self, T.untyped)
        issue.pull_request?
      end
    end
  end
end
