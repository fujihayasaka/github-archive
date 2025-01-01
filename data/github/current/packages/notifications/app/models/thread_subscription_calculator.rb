# typed: true
# frozen_string_literal: true


class ThreadSubscriptionCalculator

  attr_reader :list, :thread, :list_status_response, :thread_status_response

  def initialize(list, thread, list_status_response, thread_status_response)
    @list = list
    @thread = thread
    @list_status_response = list_status_response
    @thread_status_response = thread_status_response
  end

  def status
    if thread_status_response.failed? || list_status_response.failed?
      :unavailable
    elsif notifications_disabled_for_thread?
      :disabled
    elsif list_status_response.ignored?
      :ignoring_list
    elsif thread_status_response.events_only?
      :subscribed_to_thread_events
    elsif thread_status_response.ignored?
      :ignoring_thread
    elsif list_status_response.subscribed?
      :subscribed_to_list
    elsif list_status_response.thread_type_only?(notifications_subscription_type)
      :subscribed_to_thread_type
    elsif thread_status_response.subscribed?
      :subscribed_to_thread
    else
      :none
    end
  end

  def form_action
    case status
    when :ignoring_list, :ignoring_thread, :none
      :subscribe
    else
      :unsubscribe
    end
  end

  # Private: Are notifications disabled for discussions in this particular list?
  #
  # Returns a Boolean.
  def disable_discussions_notifications_flag_enabled?
    list.try(:disable_discussions_notifications_flag_enabled?)
  end

  # Private: Are notifications disabled for this thread?
  def notifications_disabled_for_thread?
    thread.is_a?(Discussion) && disable_discussions_notifications_flag_enabled?
  end

  # This is the type that we should check for thread type subscriptions
  # basically: for a PR this should be "PullRequest" even if the thread
  # is the pull request's issue
  def notifications_subscription_type
    newsies_thread.subscription_type || newsies_thread.type
  end

  private

  def newsies_thread
    Newsies::Thread.to_object(
      thread,
      list: Newsies::List.to_object(list)
    )
  end
end
