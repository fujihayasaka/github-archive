# typed: true
# frozen_string_literal: true

module Conduit
  module EventAdapter
    class CommentedCommit < Conduit::StratocasterEventAdapter
      COMMENT_MAX_LENGTH = 150

      def html_url = comment_html_url

      def title
        T.bind(self, T.untyped)
        "#{actor_login} #{actor_bot_identifier_text}commented on commit #{event_text}"
      end

      def partial_path = "events/commit_comment"

      def commit_sha = comment.commit_id.to_s

      def show_formatted_comment? = comment.present?

      def formatted_comment
        comment.async_truncated_body_html(COMMENT_MAX_LENGTH).sync
      end

      def icon = "comment"

      def event_text = commit_sha_summary

      def comment_html_url
        T.bind(self, T.untyped)
        comment.full_permalink
      end

      def commit_sha_summary
        T.bind(self, T.untyped)
        "#{repo_nwo}@#{commit_sha.first(10)}"
      end

      private

      def comment
        T.bind(self, T.untyped)
        subject
      end

      def repository
        T.bind(self, T.untyped)
        subject.repository
      end

      def actor_bot_identifier_text
        sender_record.bot? ? "bot " : ""
      end

      def repo_nwo = repository.name_with_display_owner
    end
  end
end
