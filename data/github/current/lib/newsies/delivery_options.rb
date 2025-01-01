# typed: true
# frozen_string_literal: true

module Newsies
  class DeliveryOptions

    include ::Newsies::Reasons

    attr_reader :delivery, :subscriber, :subscriber_wants_email_for_own_activity

    def initialize(delivery:, subscriber:, subscriber_wants_email_for_own_activity:)
      @delivery = delivery
      @subscriber = subscriber
      @subscriber_wants_email_for_own_activity = subscriber_wants_email_for_own_activity
    end

    # Public
    def handlers
      @handlers ||= if subscriber_wants_email_for_own_activity
        [Newsies::HANDLER_EMAIL]
      elsif participating?
        participating_settings
      elsif wants_vulnerabilities?
        vulnerability_settings
      elsif wants_ci_activities? || wants_approval_requests?
        settings.continuous_integration_settings
      else
        subscribed_settings
      end
    end

    def participating_settings
      participating_settings = if subscribed_to_list?
        settings.participating_settings | settings.subscribed_settings
      else
        settings.participating_settings
      end
      maybe_exclude_web_for_issues(participating_settings)
    end

    def subscribed_settings
      maybe_exclude_web_for_issues(settings.subscribed_settings)
    end

    def vulnerability_settings
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

    def settings
      @settings ||= subscriber.settings
    end

    def reason
      @reason ||= if subscriber_wants_email_for_own_activity
        :your_activity
      else
        valid_reason_from(subscriber.reason)
      end
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

    # Remove the web handler from settings for issues if already handled by notifyd.
    def maybe_exclude_web_for_issues(settings)
      return settings unless delivery.thread.is_a?(Issue)
      return settings if GitHub.enterprise?

      flags = Notifyd::Flags.new(subscriber.user)
      return settings if delivery.thread.pull_request? && !flags.enable_pull_request_notifications?
      return settings unless flags.enable_issue_notifications?
      settings - [Newsies::HANDLER_WEB]
    end
  end
end
