# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class CommitComment < Newsies::Emails::Message

      def self.matches?(comment)
        comment.is_a?(::CommitComment)
      end

      sig { returns T.nilable(::Commit) }
      def commit
        T.let(comment, ::CommitComment).commit
      end

      def subject
        "Re: [#{repository.name_with_display_owner}] #{commit&.short_message} (#{comment.commit_id[0, 7]})"
      end

      def message_id
        "<#{repository.name_with_display_owner}/commit/#{comment.commit_id}/#{comment.id}@#{GitHub.host_name}>"
      end

      def in_reply_to
        "<#{repository.name_with_display_owner}/commit/#{comment.commit_id}@#{GitHub.host_name}>"
      end

      def url
        "#{repository.permalink}/commit/#{comment.commit_id}##{comment.url_fragment}"
      end
    end
  end
end
