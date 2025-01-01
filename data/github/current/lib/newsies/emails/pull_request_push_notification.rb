# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class PullRequestPushNotification < Newsies::Emails::Message

      delegate :pull_request, :issue, :user, :repository,
               :commits, to: :comment

      def self.matches?(comment)
        comment.is_a?(::PullRequestPushNotification)
      end

      # You can't reply to a push notication since it only ever sends one notification
      def tokenized_list_address
        GitHub.urls.noreply_address
      end

      # Force the reason for this notification to reflect a push, regardless
      # of why the user was subscribed to the thread in the first place.
      #
      # Otherwise, notifications will still say `mention` if they were
      # subscribed because of a direct mention, rather than showing `push`.
      def reason
        "push"
      end

      def subject
        "Re: [#{repository.name_with_display_owner}] #{issue.title}#{issue_subject_suffix}"
      end

      def in_reply_to
        pull_request.message_id
      end

      def body
        :pull_request_push_notification
      end

      def body_html
        :pull_request_push_notification_html
      end
    end
  end
end
