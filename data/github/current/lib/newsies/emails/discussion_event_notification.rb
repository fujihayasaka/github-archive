# typed: strict
# frozen_string_literal: true

module Newsies
  module Emails
    class DiscussionEventNotification < Newsies::Emails::Message

      sig { params(comment: T.untyped).returns(T::Boolean) }
      def self.matches?(comment)
        comment.is_a?(DiscussionEvent::Notification)
      end

      sig { returns(T.nilable(::Discussion)) }
      def discussion
        T.let(comment, DiscussionEvent::Notification).discussion
      end

      sig { returns(String) }
      def subject
        "Re: [#{owner}] #{discussion&.title} (Discussion ##{discussion&.number})"
      end

      sig { returns(String) }
      def in_reply_to
        discussion&.message_id || ""
      end

      private

      sig { returns(String) }
      def owner
        if repository&.organization_discussion.present?
          repository.organization.safe_profile_name
        else
          repository.name_with_display_owner
        end
      end
    end
  end
end
