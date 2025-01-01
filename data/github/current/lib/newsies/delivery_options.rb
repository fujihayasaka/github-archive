# typed: strict
# frozen_string_literal: true

module Newsies
  class DeliveryOptions

    include ::Newsies::Reasons

    sig { returns(Delivery) }
    attr_reader :delivery
    sig { returns(Notifications::Settings::Settings) }
    attr_reader :settings
    sig { returns(User) }
    attr_reader :user

    sig { params(delivery: Delivery, reason: T.any(String, Symbol), settings: Notifications::Settings::Settings, user: User).void }
    def initialize(delivery:, reason:, settings:, user:)
      @delivery = delivery
      @reason = reason
      @settings = settings
      @user = user
      @subscribed_to_list = T.let(nil, T.nilable(T::Boolean))
    end

    # Public
    sig { returns(T::Array[String]) }
    def handlers
      if participating?
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

    sig { returns(T.nilable(Symbol)) }
    def reason
      valid_reason_from(@reason)
    end

    private

    sig { returns(T::Array[String]) }
    def participating_handlers
      handlers = []
      if subscribed_to_list?
        if settings.participant&.email || settings.watcher&.email
          handlers << Newsies::HANDLER_EMAIL
        end
        if settings.participant&.web || settings.watcher&.web
          handlers << Newsies::HANDLER_WEB
        end
      else
        handlers << Newsies::HANDLER_EMAIL if settings.participant&.email
        handlers << Newsies::HANDLER_WEB if settings.participant&.web
      end
      handlers = maybe_exclude_web_for_issues(handlers)
      maybe_exclude_email(handlers)
    end

    sig { returns(T::Array[String]) }
    def subscribed_handlers
      handlers = []
      handlers << Newsies::HANDLER_EMAIL if settings.watcher&.email
      handlers << Newsies::HANDLER_WEB if settings.watcher&.web
      handlers = maybe_exclude_web_for_issues(handlers)
      maybe_exclude_email(handlers)
    end

    sig { returns(T::Array[String]) }
    def vulnerability_handlers
      handlers = []
      if delivery.thread_type == "Issue" && subscribed_to_list?
        # This makes sure that we respect a user's "watching" settings for
        # security pull requests (created by Dependabot). Those are both a type
        # of security alert notification and a normal pull request, and so should
        # respect both types of settings.
        if settings.vulnerability&.email || settings.watcher&.email
          handlers << Newsies::HANDLER_EMAIL
        end
        if settings.vulnerability&.web || settings.watcher&.web
          handlers << Newsies::HANDLER_WEB
        end
      elsif delivery.comment_type == "RepositoryVulnerabilityAlert::WebNotification"
        handlers << Newsies::HANDLER_WEB if settings.vulnerability&.web
      else
        handlers << Newsies::HANDLER_EMAIL if settings.vulnerability&.email
        handlers << Newsies::HANDLER_WEB if settings.vulnerability&.web
      end
      handlers
    end

    sig { returns(T::Array[String]) }
    def ci_activity_handlers
      # Actions notifications are delivered through notifyd in dotcom/proxima.
      return [] unless GitHub.enterprise?
      # Do nothing if the recipient is only interested in failed actions but the
      # action finished successfully.
      return [] if delivery.comment.respond_to?(:deliver?) && !delivery.comment.deliver?(settings.actions)
      handlers = []
      handlers << Newsies::HANDLER_EMAIL if settings.actions&.email
      handlers << Newsies::HANDLER_WEB if settings.actions&.web
      handlers
    end

    sig { returns(T::Array[String]) }
    def approval_request_handlers
      # Actions notifications are delivered through notifyd in dotcom/proxima.
      return [] unless GitHub.enterprise?
      handlers = []
      handlers << Newsies::HANDLER_EMAIL if settings.actions&.email
      handlers << Newsies::HANDLER_WEB if settings.actions&.web
      handlers
    end

    sig { returns(T::Boolean) }
    def subscribed_to_list?
      return @subscribed_to_list unless @subscribed_to_list.nil?
      @subscribed_to_list = GitHub.newsies.subscription_status(user, delivery.list).subscribed?
    end

    sig { returns(T::Boolean) }
    def participating?
      ::Newsies::Reasons::Participating.include?(reason)
    end

    sig { returns(T::Boolean) }
    def wants_vulnerabilities?
      ::Newsies::Reasons::Vulnerability.equal?(reason)
    end

    sig { returns(T::Boolean) }
    def wants_ci_activities?
      ::Newsies::Reasons::ContinuousIntegration.equal?(reason)
    end

    sig { returns(T::Boolean) }
    def wants_approval_requests?
      ::Newsies::Reasons::ApprovalRequested.equal?(reason)
    end

    # Remove the web handler from handlers for issues if already handled by notifyd.
    sig { params(handlers: T::Array[String]).returns(T::Array[String]) }
    def maybe_exclude_web_for_issues(handlers)
      return handlers unless delivery.thread.is_a?(Issue)
      return handlers if GitHub.enterprise?

      flags = Notifyd::Flags.new(user)
      return handlers if delivery.thread.pull_request? && !flags.enable_pull_request_notifications?
      return handlers unless flags.enable_issue_notifications?
      handlers - [Newsies::HANDLER_WEB]
    end

    # Remove the email handler from handlers depending on custom email updates settings
    sig { params(handlers: T::Array[String]).returns(T::Array[String]) }
    def maybe_exclude_email(handlers)
      if exclude_email?
        handlers - [Newsies::HANDLER_EMAIL]
      else
        handlers
      end
    end

    sig { returns(T::Boolean) }
    def exclude_email?
      return true if delivery.comment.is_a?(::IssueComment) && !settings.issue_comment_email
      return true if delivery.comment.is_a?(::PullRequestPushNotification) && !settings.pull_request_push_email
      return true if delivery.comment.is_a?(::PullRequestReview) && !settings.pull_request_review_email
      return true if delivery.comment.is_a?(::PullRequestReviewComment) && !settings.pull_request_review_email
      false
    end
  end
end
