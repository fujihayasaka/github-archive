# typed: true
# frozen_string_literal: true

module Notifications
  class ThreadSubscriptionComponent < ApplicationComponent
    renders_one :fallback_error
    renders_one :spinner

    def initialize(
      display_explanation_text: false,
      form_path: nil,
      list:,
      thread:,
      websocket_url: nil,
      deferred: false
    )
      @display_explanation_text = display_explanation_text
      @form_path = form_path
      @list = list
      @thread = thread
      @websocket_url = websocket_url
      @deferred = deferred
    end

    private

    attr_reader :list, :thread, :deferred
    alias_method :deferred?, :deferred

    def display_explanation_text?
      @display_explanation_text
    end

    def channel_list
      channels = [
        GitHub::WebSocket::Channels.list_subscription(current_user, list),
        GitHub::WebSocket::Channels.thread_subscription(current_user, list, thread_id),
      ].map do |channel|
        live_update_view_channel(channel)
      end

      channels.join(" ")
    end

    def show_notifications_header?
      # Not shown for gists and commits because they're not displayed in a
      # sidebar where a 'Notifications' header makes sense.
      return false if thread.is_a?(Gist)
      return false if thread.is_a?(Commit)

      return true if thread.is_a?(Discussion)
      return true if use_notifyd_primary_for_thread?

      false
    end

    # The websocket_url is used for async HTML loading, also with <include-fragment>
    memoize def websocket_url
      @websocket_url || notifications_thread_subscription_path(repository_id: list_id, thread_id: thread_id, thread_class: thread_class)
    end

    memoize def form_path
      @form_path || notifications_thread_subscribe_path
    end

    def form_action
      thread_subscription.form_action.to_s
    end

    # Public: Are notifications disabled for this thread?
    def notifications_disabled_for_thread?
      thread_subscription.notifications_disabled_for_thread?
    end

    def explanation_text
      case thread_status
      when :unavailable
        "Notifications are unavailable."
      when :subscribed_to_thread_events
        "You’re receiving notifications because you chose custom settings for this thread."
      when :subscribed_to_thread
        "You’re receiving notifications because #{GitHub.newsies.reason_in_words(thread_status_response.reason)}."
      when :subscribed_to_thread_type
        "You’re receiving notifications because you are watching #{notifications_subscription_type.underscore.humanize.downcase.pluralize} on this repository."
      when :subscribed_to_list
        "You’re receiving notifications because you’re watching this repository."
      when :ignoring_thread
        "You’re not receiving notifications from this thread."
      when :ignoring_list
        "You’re ignoring this repository."
      when :disabled
        "Notifications are disabled for #{thread_human_name.pluralize} in this repository."
      else
        "You’re not receiving notifications from this thread."
      end
    end

    def button_icon
      return :"bell" if form_action == "subscribe"
      :"bell-slash" if form_action == "unsubscribe"
    end

    def button_text
      return "Subscribe" if form_action == "subscribe"
      "Unsubscribe" if form_action == "unsubscribe"
    end

    memoize def list_id
      Newsies::List.to_id(list)
    end

    memoize def thread_class
      Newsies::Thread.to_type(thread).demodulize
    end

    # Public: Get a human-friendly name for the kind of thread this is.
    #
    # Returns a String like "discussion", "issue", or "pull request".
    def thread_human_name
      if thread.respond_to?(:pull_request?) && thread.pull_request?
        "pull request"
      else
        thread_class.underscore.humanize.downcase
      end
    end

    def thread_id
      newsies_thread.id
    end

    memoize def newsies_thread
      Newsies::Thread.to_object(
        thread,
        list: Newsies::List.to_object(list)
      )
    end

    # This is the type that we should check for thread type subscriptions
    # basically: for a PR this should be "PullRequest" even if the thread
    # is the pull request's issue
    def notifications_subscription_type
      thread_subscription.notifications_subscription_type
    end

    memoize def thread_status
      thread_subscription.status
    end

    def custom_notifications_supported_for_thread?
      return false unless list.is_a?(Repository)
      return false if use_notifyd_primary_for_thread?

      subscribable_events.present?
    end

    def subscribable_events
      # treat an issue with a pull_request as a pull request
      is_pull_request = thread.is_a?(PullRequest) || (thread.is_a?(Issue) && thread.pull_request?)
      return %w[merged closed reopened] if is_pull_request

      return %w[closed reopened] if thread.is_a?(Issue)

      []
    end

    memoize def repo_status_response
      GitHub.newsies.subscription_status(current_user, list)
    end

    memoize def thread_status_response
      Notifications::Subscriptions.subscription_status(current_user, list, thread)
    end

    memoize def use_notifyd_primary_for_thread?
      thread.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(current_user)
    end

    memoize def thread_subscription
      ThreadSubscriptionCalculator.new(list, thread, repo_status_response, thread_status_response)
    end
  end
end
