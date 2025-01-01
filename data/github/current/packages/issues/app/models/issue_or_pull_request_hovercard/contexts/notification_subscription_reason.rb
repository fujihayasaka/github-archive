# typed: true
# frozen_string_literal: true

module IssueOrPullRequestHovercard::Contexts
  class NotificationSubscriptionReason < Hovercard::Contexts::Base
    # Public: Build a NotificationSubscriptionReason context
    #
    # Returns a Promise that resolves to either a NotificationSubscriptionReason object or nil.
    def self.async_resolve(issue_or_pull_request:, viewer:)
      Resolver.new(issue_or_pull_request: issue_or_pull_request, viewer: viewer).async_resolve
    end

    def initialize(repo_status:, thread_status:)
      @repo_status = repo_status
      @thread_status = thread_status
    end

    attr_reader :repo_status, :thread_status

    def message
      if thread_status.subscribed?
        "You’re receiving notifications because #{GitHub.newsies.reason_in_words(thread_status.reason)}."
      elsif repo_status.subscribed? && !thread_status.ignored?
        "You’re receiving notifications because you’re watching this repository."
      else
        "You are subscribed to receive notifications for this thread."
      end
    end

    def octicon
      "note"
    end

    def platform_type_name
      "GenericHovercardContext"
    end

    class Resolver
      attr_reader :viewer, :issue_or_pull_request, :repository

      def initialize(issue_or_pull_request:, viewer:)
        @issue_or_pull_request = issue_or_pull_request
        @viewer = viewer
        @repository = repository_from_issue
      end

      def async_resolve
        if thread_status_response.failed? || repo_status_response.failed? ||
           thread_status.ignored? || not_watching_thread_or_repo?
          Promise.resolve(nil)
        else
          context = NotificationSubscriptionReason.new(
            repo_status: repo_status,
            thread_status: thread_status,
          )
          Promise.resolve(context)
        end
      end

      private

      def repo_status_response
        @repo_status_response ||= GitHub.newsies.subscription_status(viewer, repository)
      end

      def thread_status_response
        @thread_status_response ||= Notifications::Subscriptions.subscription_status(viewer, repository, issue_or_pull_request.to_issue)
      end

      def repo_status
        @repo_status ||= repo_status_response.value
      end

      def thread_status
        @thread_status ||= thread_status_response.value
      end

      def repository_from_issue
        issue_or_pull_request.repository
      end

      def not_watching_thread_or_repo?
        !thread_status.subscribed? && !repo_status.subscribed?
      end
    end
  end
end
