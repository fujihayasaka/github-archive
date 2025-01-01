# typed: true
# frozen_string_literal: true

module Newsies
  class DeliveryOptions

    include ::Newsies::Reasons

    attr_reader :delivery, :subscriber, :settings, :user, :subscriber_wants_email_for_own_activity

    def initialize(delivery:, subscriber:, settings:, user:, subscriber_wants_email_for_own_activity:)
      @delivery = delivery
      @subscriber = subscriber
      @settings = settings
      @user = user
      @subscriber_wants_email_for_own_activity = subscriber_wants_email_for_own_activity
    end

    # Public
    def handlers
      @handlers ||= if subscriber_wants_email_for_own_activity
        [Newsies::HANDLER_EMAIL]
      elsif participating?
        participating_handlers
      elsif wants_vulnerabilities?
        vulnerability_handlers
      elsif wants_ci_activities?
        ci_activity_handlers
      elsif wants_approval_requests?
        approval_request_handlers
      else
        subscribed_handlers
      end
    end

    def reason
      @reason ||= if subscriber_wants_email_for_own_activity
        :your_activity
      else
        valid_reason_from(subscriber.reason)
      end
    end

    private

    def participating_handlers
      handlers = if subscribed_to_list?
        settings.participating_settings | settings.subscribed_settings
      else
        settings.participating_settings
      end
      handlers = maybe_exclude_web_for_issues(handlers)
      maybe_exclude_email(handlers)
    end

    def subscribed_handlers
      handlers = maybe_exclude_web_for_issues(settings.subscribed_settings)
      maybe_exclude_email(handlers)
    end

    def vulnerability_handlers
      if delivery.thread_type == "Issue" && subscribed_to_list?
        # This makes sure that we respect a user's "watching" settings for
        # security pull requests (created by Dependabot). Those are both a type
        # of security alert notification and a normal pull request, and so should
        # respect both types of settings.
        settings.vulnerability_settings | settings.subscribed_settings
      elsif delivery.comment_type == "RepositoryVulnerabilityAlert::WebNotification"
        settings.vulnerability_settings & ["web"]
      else
        settings.vulnerability_settings
      end
    end

    def ci_activity_handlers
      # Actions notifications are delivered through notifyd in dotcom/proxima.
      return [] unless GitHub.enterprise?
      # Do nothing if the recipient is only interested in failed actions but the
      # action finished successfully.
      return [] if delivery.comment.respond_to?(:deliver?) && !delivery.comment.deliver?(settings)
      settings.continuous_integration_settings
    end

    def approval_request_handlers
      # Actions notifications are delivered through notifyd in dotcom/proxima.
      return [] unless GitHub.enterprise?
      settings.continuous_integration_settings
    end

    def subscribed_to_list?
      return @subscribed_to_list if defined? @subscribed_to_list
      @subscribed_to_list = GitHub.newsies.subscription_status(settings, delivery.list).subscribed?
    end

    def participating?
      ::Newsies::Reasons::Participating.include?(reason)
    end

    def wants_vulnerabilities?
      ::Newsies::Reasons::Vulnerability.equal?(reason)
    end

    def wants_ci_activities?
      ::Newsies::Reasons::ContinuousIntegration.equal?(reason)
    end

    def wants_approval_requests?
      ::Newsies::Reasons::ApprovalRequested.equal?(reason)
    end

    # Remove the web handler from handlers for issues if already handled by notifyd.
    def maybe_exclude_web_for_issues(handlers)
      return handlers unless delivery.thread.is_a?(Issue)
      return handlers if GitHub.enterprise?

      flags = Notifyd::Flags.new(user)
      return handlers if delivery.thread.pull_request? && !flags.enable_pull_request_notifications?
      return handlers unless flags.enable_issue_notifications?
      handlers - [Newsies::HANDLER_WEB]
    end

    # Remove the email handler from handlers depending on custom email updates settings
    def maybe_exclude_email(handlers)
      if exclude_email?
        handlers - [Newsies::HANDLER_EMAIL]
      else
        handlers
      end
    end

    def exclude_email?
      return true if delivery.comment.is_a?(::IssueComment) && !settings.try(:notify_comment_email?)
      return true if delivery.comment.is_a?(::PullRequestPushNotification) && !settings.try(:notify_pull_request_push_email?)
      return true if delivery.comment.is_a?(::PullRequestReview) && !settings.try(:notify_pull_request_review_email?)
      return true if delivery.comment.is_a?(::PullRequestReviewComment) && !settings.try(:notify_pull_request_review_email?)
      false
    end
  end
end
