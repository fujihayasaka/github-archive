# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    # This is a small helper class used to check whether an issue has email
    # delivery enabled in Notifyd. If this is the case, Newsies should skip
    # email delivery
    # The idea is to use this check in emails that are related to issues, like
    # Issue, IssueComment and IssueEvent
    class IssueDeliveryCheck
      attr_reader :issue, :actor, :recipient, :trigger

      def initialize(issue, actor, recipient, trigger)
        @issue = issue
        @actor = actor
        @recipient = recipient
        @trigger = trigger
      end

      # Checks if Issue notifications for the recipient are processed by Notifyd.
      def notifyd_enabled?
        flags = Notifyd::Flags.new(recipient)
        return false if issue.pull_request? && !flags.enable_pull_request_notifications?
        return true if flags.enable_issue_notifications?

        # if user doesn't have notifyd_issue_watch_activity_notify enabled, notification can still be processed by Notifyd
        # if user has label subscriptions enabled and issue has a label that user is subscribed to
        label_subscription_enabled?
      end

      def label_subscription_enabled?
        # we do not support label subscriptions for issue updates ans close events
        return false if %w[updated closed].include?(trigger)

        repo = issue.repository
        label_subscriptions_enabled = Notifyd::Flags.new(recipient).label_subscriptions?(repo)
        return false unless label_subscriptions_enabled

        return false if issue.labels.empty?

        subscribed_repo_labels = repo.subscribed_labels(recipient)

        # check if user is subscribed to any of the issue labels
        issue.labels.any? do |issue_label|
          subscribed_repo_labels.any? { |repo_label| issue_label.id == repo_label.id }
        end
      end
    end
  end
end
