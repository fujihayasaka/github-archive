# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class DiscussionPost < Newsies::Emails::Message
      extend ActionView::Helpers::TextHelper

      def team
        notifications_list
      end

      sig { returns ::DiscussionPost }
      def discussion_post
        comment
      end

      def self.matches?(comment)
        comment.is_a?(::DiscussionPost)
      end

      def self.subject_for(discussion_post)
        "[#{discussion_post.team.name_with_display_owner}] #{discussion_post.title} (##{discussion_post.number})"
      end

      def subject
        self.class.subject_for(discussion_post)
      end

      # Override Gmail ViewAction link to read "View Discussion" (rather than "View Discussion Post").
      def conversation_type
        "Discussion"
      end
    end
  end
end
