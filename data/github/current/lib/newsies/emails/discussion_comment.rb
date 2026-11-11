# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class DiscussionComment < Newsies::Emails::Message
      def self.matches?(comment)
        comment.is_a?(::DiscussionComment)
      end

      sig { returns(T.nilable(::Discussion)) }
      def discussion
        T.let(comment, ::DiscussionComment).discussion
      end

      def in_reply_to
        discussion&.message_id
      end

      def subject
        "Re: [#{repository.name_with_display_owner}] #{discussion&.title} (Discussion ##{discussion&.number})"
      end

      private

      sig { returns T.nilable(Time) }
      def thread_root_created_at
        discussion&.created_at
      end
    end
  end
end
