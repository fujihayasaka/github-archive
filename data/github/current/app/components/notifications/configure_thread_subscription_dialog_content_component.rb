# typed: true
# frozen_string_literal: true

module Notifications
  class ConfigureThreadSubscriptionDialogContentComponent < ApplicationComponent
    CUSTOM_SUBSCRIPTION_THREAD_STATUSES = %i(subscribed_to_thread_events).freeze
    SUBSCRIBED_THREAD_STATUSES = %i(subscribed_to_list subscribed_to_thread).freeze
    UNSUBSCRIBED_THREAD_STATUSES = %i(none ignoring_thread).freeze

    def initialize(list:, thread:)
      @list = list
      @thread = thread
    end

    private

    attr_reader :list, :thread

    def unsubscribed?
      thread_status.in?(UNSUBSCRIBED_THREAD_STATUSES)
    end

    def subscribed?
      thread_status.in?(SUBSCRIBED_THREAD_STATUSES)
    end

    def custom_subscription?
      thread_status.in?(CUSTOM_SUBSCRIPTION_THREAD_STATUSES)
    end

    def form_path
      notifications_thread_subscribe_path
    end

    # Public: Are notifications disabled for discussions in this particular list?
    #
    # Returns a Boolean.
    def disable_discussions_notifications_flag_enabled?
      list.try(:disable_discussions_notifications_flag_enabled?)
    end

    # Public: Are notifications disabled for this thread?
    def notifications_disabled_for_thread?
      thread.is_a?(Discussion) && disable_discussions_notifications_flag_enabled?
    end

    memoize def list_id
      Newsies::List.to_id(list)
    end

    memoize def thread_class
      Newsies::Thread.to_type(thread).demodulize
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
      newsies_thread.subscription_type || newsies_thread.type
    end

    memoize def thread_status
      if thread_status_response.failed? || repo_status_response.failed?
        :unavailable
      elsif notifications_disabled_for_thread?
        :disabled
      elsif repo_status_response.ignored?
        :ignoring_list
      elsif thread_status_response.events_only?
        :subscribed_to_thread_events
      elsif thread_status_response.ignored?
        :ignoring_thread
      elsif repo_status_response.subscribed?
        :subscribed_to_list
      elsif repo_status_response.thread_type_only?(notifications_subscription_type)
        :subscribed_to_thread_type
      elsif thread_status_response.subscribed?
        :subscribed_to_thread
      else
        :none
      end
    end

    def subscribed_to_event?(event)
      thread_status == :subscribed_to_thread_events && thread_status_response.events.include?(event)
    end

    def subscribable_events
      # treat an issue with a pull_request as a pull request
      is_pull_request = thread.is_a?(PullRequest) || (thread.is_a?(Issue) && thread.pull_request?)
      return %w[merged closed reopened] if is_pull_request

      return %w[closed reopened] if thread.is_a?(Issue)

      []
    end

    def visible_thread_type
      visible_thread.class.name.underscore.humanize(capitalize: false)
    end

    # What action should selecting "subscribe" from the modal take?
    def modal_subscribe_action
      if repo_status_response.subscribed? && !thread_status_response.valid?
        # The user is already watching the repo, and no thread subscription row exists (for
        # unsubscribing from this thread) that needs to be overwritten, so there is no need to
        # create a thread subscription row.
        #
        # This helps maintain consistency with the fact that outside the modal we don't even present
        # the "Subscribe" option if you're watching the repo, so we don't create a thread
        # subscription row there either.
        :noop
      else
        # Otherwise, we indeed want to create or update a thread subscription row.
        :subscribe
      end
    end

    memoize def repo_status_response
      GitHub.newsies.subscription_status(current_user, list)
    end

    memoize def thread_status_response
      Subscriptions.subscription_status(current_user, list, thread)
    end

    memoize def visible_thread
      (thread.is_a?(Issue) && thread.pull_request?) ? thread.pull_request : thread
    end
  end
end
