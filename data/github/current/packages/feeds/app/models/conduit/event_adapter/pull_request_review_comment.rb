# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class PullRequestReviewComment < Conduit::StratocasterEventAdapter
      COMMENT_REVIEW_MAX_LENGTH = 150

      def html_url
        url
      end

      # Combine actor login, bot identifier (if present), and action text.
      def title
        T.bind(self, T.untyped)
        "#{actor_login} #{actor_bot_identifier_text}commented on pull request #{pull_text}"
      end

      def partial_path
        "events/pull_request_review_comment"
      end

      def url
        T.bind(self, T.untyped)
        pull_request_review_comment.url
      end

      def actor_bot_identifier_text
        sender_record.bot? ? "bot " : ""
      end

      def pull_comment_url
        T.bind(self, T.untyped)
        pull_request_review_comment.url || pull_request.url
      end

      def pull_request_title
        T.bind(self, T.untyped)
        pull_request.title
      end

      def pull_text
        if pull_request.permalink
          "#{repo_nwo}##{pull_request.number}"
        else
          "(deleted)"
        end
      end

      def comment_body
        T.bind(self, T.untyped)
        payload[:comment][:body]
      end

      def formatted_comment
        T.bind(self, T.untyped)
        HTMLTruncator.new(comment_body, COMMENT_REVIEW_MAX_LENGTH).to_html(wrap: false)
      end

      def icon
        "issues_comment"
      end

      private

      def pull_request_review_comment
        T.bind(self, T.untyped)
        subject
      end

      def pull_request
        T.bind(self, T.untyped)
        subject.pull_request
      end

      def repository
        T.bind(self, T.untyped)
        subject.repository
      end

      def repo_nwo
        repository.name_with_display_owner
      end
    end
  end
end
