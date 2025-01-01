# typed: true
# frozen_string_literal: true

module Newsies
  class ThreadSubscriptionManager
    # Ensures that the user will no longer receive notifications for this
    # thread until they are resubscribed.
    #
    # This method does different things in the database depending on whether
    # the user is list or thread-type subscribed or not.
    def self.unsubscribe_from_thread(user, list, thread)
      newsies_list = Newsies::List.to_object(list)
      newsies_thread = Newsies::Thread.to_object(thread, list: newsies_list)

      # If the user is subscribed to the list, then we must insert an "ignoring" thread
      # subscription to block notifications that would otherwise be sent to the list.
      #
      # If the user is ignoring the list, we fall through and delete the thread subscription
      # at the end.
      if ListSubscription.for_user(user.id).for_list(newsies_list).excluding_ignored.exists?
        Newsies::ThreadSubscription.ignore(user.id, newsies_thread)
        async_notify_subscription_status_change(user.id, newsies_list, newsies_thread)
        return
      end

      # If the user is subscribed to the thread type, then we must insert
      # an "ignoring" record for the thread to block notifications that
      # that would otherwise be sent due to the thread type subscription
      if ThreadTypeSubscription.for_user(user.id).for_list(newsies_list).for_thread_type(newsies_thread.subscription_type).exists?
        Newsies::ThreadSubscription.ignore(user.id, newsies_thread)
        async_notify_subscription_status_change(user.id, newsies_list, newsies_thread)
        return
      end

      # The user has no list-level subscriptions, so to unsubscribe from
      # future notifications on this thread (until they are re-subscribed)
      # we can simply delete the thread subscription
      Newsies::ThreadSubscription.for_user(user.id).for_thread(newsies_thread).destroy_all
      async_notify_subscription_status_change(user.id, newsies_list, newsies_thread)
    end

    def self.async_notify_subscription_status_change(user_id, newsies_list, newsies_thread)
      # Commit don't respond to #id. Well they do, but output a deprecated
      # message. So we can't even respond_to? check them.
      return if newsies_thread.type == "Grit::Commit"

      NotifySubscriptionStatusChangeJob.perform_later(
        user_id,
        newsies_list.id,
        newsies_thread.id,
        { reason: "thread subscription status changed" },
        newsies_list.type
      )
    end
  end
end
