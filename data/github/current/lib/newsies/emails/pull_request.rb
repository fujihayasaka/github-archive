# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class PullRequest < Newsies::Emails::Issue
      def self.matches?(comment)
        comment.is_a?(::Issue) && comment.pull_request?
      end

      # Public: User-facing conversation type.
      #
      # This is overridden here because comment.notifications_thread is the
      # PR's issue and not the PR itself.
      #
      # Returns a String name.
      sig { returns String }
      def conversation_type
        "Pull Request"
      end

      def body
        :pull_request
      end

      def body_html
        :pull_request_html
      end

      # Overridden here because the super's comment is the PR's issue and not the PR itself.
      sig { returns ::PullRequest }
      def comment
        T.must_because(issue.pull_request) { "#matches? calls #pull_request? which ensures it's non-nil" }
      end

      def dependency_update_alert
        return unless dependency_update_visible?

        dependency_update = comment.most_recent_vulnerability_dependency_update
        dependency_update&.repository_vulnerability_alert
      end

      def dependency_update_visible?
        repository.automated_security_updates_visible_to?(user)
      end

      def url_dependabot_help_with_tracking_params
        dependabot_help_url = GitHub.dependabot_security_updates_help_url
        return dependabot_help_url unless newsies_pr_email_click_tracking_enabled?

        add_tracking_params(dependabot_help_url, "pr_dependabot_help_click")
      end

      def url_open_with_tracking_params(open_url, event)
        return open_url unless newsies_pr_email_click_tracking_enabled?

        add_tracking_params(open_url, event)
      end
    end
  end
end
