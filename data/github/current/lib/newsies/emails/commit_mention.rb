# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class CommitMention < Newsies::Emails::Message

      def self.matches?(comment)
        comment.is_a?(::CommitMention)
      end

      delegate :commit, to: :comment

      def subject
        "[#{repository.name_with_display_owner}] #{commit.short_message} (#{T.must(commit_id)[0, 7]})"
      end

      def content
        commit.message
      end

      def content_html
        commit.message_body_html
      end

      def url
        "#{repository.permalink}/commit/#{commit_id}"
      end

      def message_id
        "<#{repository.name_with_display_owner}/commit/#{commit_id}@#{GitHub.host_name}>"
      end

      # Returns true to support generating an HTML email body.
      def body_html?
        true
      end

      private

      sig { returns T.nilable(String) }
      def commit_id
        T.let(comment, ::CommitMention).commit_id
      end
    end
  end
end
