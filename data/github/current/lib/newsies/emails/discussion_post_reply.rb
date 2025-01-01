# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class DiscussionPostReply < Newsies::Emails::Message
      extend T::Sig
      include ActionView::Helpers::TextHelper

      def team
        notifications_list
      end

      sig { returns ::DiscussionPostReply }
      def discussion_post_reply
        comment
      end

      def self.matches?(comment)
        comment.is_a?(::DiscussionPostReply)
      end

      def subject
        "Re: #{DiscussionPost.subject_for(discussion_post)}"
      end

      def in_reply_to
        discussion_post&.message_id
      end

      # Override Gmail ViewAction link to read "View Discussion" (rather than "View Discussion Post").
      def conversation_type
        "Discussion"
      end

      private

      sig { returns(T.nilable(::DiscussionPost)) }
      def discussion_post
        discussion_post_reply.discussion_post
      end
    end
  end
end
