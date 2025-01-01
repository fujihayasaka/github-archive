# typed: true
# frozen_string_literal: true

# ActiveRecord mixin for models that can be subscribed to.
#
# Objects that include this mixin must implement the #notifications_thread
# method. The object returned from this method must respond to #id. The object's
# class name is combined with the id to form thread storage keys.
module Notifications
  module SubscribableThread
    extend T::Helpers
    requires_ancestor { Kernel }

    def notifications_list
      async_notifications_list.sync
    end

    def async_notifications_list
      raise NotImplementedError, "SubscribableThread error: Syncing notifications_list"
    end

    def notifications_thread
      raise NotImplementedError, "SubscribableThread error: Getting notifications_thread"
    end

    def notifications_author
      raise NotImplementedError, "SubscribableThread error: Getting notifications_author"
    end

    # Returns true if thread subscription should be done in notifyd for the user and reason, false otherwise.
    #
    # user    - The User that wants to subscribe to the thread.
    # reason  - String reason for the subscription. Ex: "mention"
    def subscribe_in_notifyd?(user, reason)
      false
    end

    # Returns true if thread unsubscription should be done in notifyd for the user, false otherwise.
    #
    # user    - The User that wants to subscribe to the thread.
    def unsubscribe_in_notifyd?(user)
      false
    end

    # Returns the members of a team that can be subscribed to the thread.
    #
    # team - The team
    #
    # Returns an Array of Users
    def subscribable_team_members(team)
      team.notifiable_members
    end

    # Public: Subscribes a User to receive notifications from this Conversation::Subject.
    #
    # user    - The User that receives the notifications.
    # reason  - Optional String reason for the subscription. Ex: "mention"
    #
    # Returns true if the subscription is successful.
    def subscribe(user, reason = nil, events = [])
      return unless notifications_thread.subscribable_by?(user)

      GitHub.dogstats.increment("notifications.subscribable.subscribe", tags: ["reason:#{reason || "NONE"}"])

      response = Subscriptions.subscribe_to_thread(user, notifications_list, notifications_thread, reason, events)
      if response.success?
        async_notify_subscription_status_change(user, :subscribed)
      end
      response.success?
    end

    def subscribe_all(users, reason = nil)
      subscribable_users = users.select { |user| notifications_thread.subscribable_by?(user) } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      response = GitHub.newsies.subscribe_all_to_thread(subscribable_users, notifications_list, notifications_thread, reason)
      if response.success?
        subscribable_users.each { |user| async_notify_subscription_status_change(user, :subscribed) }
      end

      response.success?
    end

    # Public: Unsubscribes a User from receiving any more notifications for this
    # Subscribable, until the next time, they are mentioned/team-mentioned.
    #
    # user - The User that won't receive any more notifications.
    #
    # Returns true if the unsubscribe event is successful.
    def unsubscribe(user)
      response = Subscriptions.unsubscribe_from_thread(user, notifications_thread)
      if response.success?
        async_notify_subscription_status_change(user, :unsubscribed)
      end
      response.success?
    end

    # Public: Checks to see if the User is subscribed to the Issue.
    #
    # user - The User to check.
    #
    # Returns true if the User is subscribed.
    def subscribed?(user)
      subscription_status(user).subscribed?
    end

    # Public: Gets the subscription status for the current user and this Issue.
    #
    # user - The User to check.
    #
    # Returns a Newsies::Responses::Subscription.
    def subscription_status(user)
      Subscriptions.subscription_status(user, notifications_list, notifications_thread)
    end

    # Public: Async version of subscription_status.
    #
    # user - The User to check.
    #
    # Returns a Promise.
    def async_subscription_status(user)
      async_notifications_list.then do
        subscription_status(user)
      end
    end

    # Public: Determines if this User is able to subscribe to this thread.
    #
    # user   - A User.
    # author - Author of the content being posted.
    #
    # Returns a Boolean.
    def subscribable_by?(user, author = nil)
      subscribable_to_author?(user, author) && subscribable_to_list?(user)
    end

    # Public: Determines if this User can subscribe to items from this thread's
    # author.
    #
    # user   - A User.
    # author - Author of the content being posted.  Defaults to #user.
    #
    # Returns a Boolean.
    def subscribable_to_author?(user, author = nil)
      return true unless user
      author ||= notifications_author
      other_users = [author, notifications_list.owner].delete_if do |u|
        u.nil? || u == user
      end
      return true if other_users.blank?

      if avoid_reason = user.avoidable_reason_for(*other_users)
        GitHub.logger.info("user cannot subscribe to this author's threads", {
          "code.namespace" => "Subscribable",
          "code.function" => "subscribable_to_author",
          "gh.user.id" => user.id,
          "gh.user.login" => user.display_login,
          "gh.notifications.avoided_users_ids" => other_users.map(&:id),
          "gh.notifications.avoided_users_logins" => other_users.map(&:display_login)
        })
        return false
      end

      true
    end

    # Public: Determines if this User can subscribe to this thread's list.
    #
    # user - A User.
    #
    # Returns a Boolean.
    def subscribable_to_list?(user)
      notifications_list.public? ||
        notifications_list.readable_by?(user) ||
        (notifications_list.kind_of?(Repository) && notifications_list.resources.contents.readable_by?(user))
    end

    # Internal: Notify web socket that subscription status has changed.
    #
    # user       - A User
    # new_status - Subscription state the status has moved to (default: subscribed)
    def async_notify_subscription_status_change(user, new_status = :subscribed)
      # Just ignore if user is nil. Need to check assumptions here.
      return unless user

      # Commit don't respond to #id. Well they do, but output a deprecated
      # message. So we can't even respond_to? check them.
      return if notifications_thread.kind_of?(Commit)

      data = {
        reason: "thread subscription status changed to #{new_status}",
      }
      NotifySubscriptionStatusChangeJob.perform_later(user.id, notifications_list.id, notifications_thread.id, data, notifications_list.class.name)
    end
  end
end
