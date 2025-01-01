# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class PullRequestComment < Newsies::Emails::IssueComment
      def self.matches?(comment)
        comment.is_a?(::IssueComment) && comment.issue&.pull_request?
      end

      sig { returns T.nilable(::PullRequest) }
      def pull_request
        issue&.pull_request
      end

      # Public: User-facing conversation type.
      #
      # This is overridden here beacuse comment.notifications_thread is the
      # PR's issue and not the PR itself.
      #
      # Retuns a String name.
      def conversation_type
        "Pull Request"
      end

      def message_id
        "<#{repository.name_with_display_owner}/pull/#{issue&.number}/c#{comment.id}@#{GitHub.host_name}>"
      end

      def in_reply_to
        pull_request&.message_id
      end

      def url
        "#{pull_request&.permalink}#issuecomment-#{comment.id}"
      end
    end
  end
end
