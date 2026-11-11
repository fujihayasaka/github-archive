# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class PullRequestPushNotification < Newsies::Emails::Message
      delegate :pull_request, :issue, :repository, :commits, to: :comment

      def self.matches?(comment)
        comment.is_a?(::PullRequestPushNotification)
      end

      # You can't reply to a push notification since it only ever sends one notification
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

      def url_user_with_tracking_params
        url = comment.user_url(user_url(comment.user))
        return url unless newsies_pr_email_click_tracking_enabled?

        add_tracking_params(url, "pr_push_user_click")
      end

      def url_commit_with_tracking_params(commit_url)
        return commit_url unless newsies_pr_email_click_tracking_enabled?

        add_tracking_params(commit_url, "pr_push_commit_click")
      end
    end
  end
end
