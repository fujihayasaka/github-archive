# typed: true
# frozen_string_literal: true

# ActiveRecord mixin for notification lists that can be subscribed to.
module Notifications
  module SubscribableList
    extend T::Helpers
    requires_ancestor { Kernel }

    # used in SubscribableThread#subscribable_to_list?
    def public?
      raise NotImplementedError, "SubscribableList error: User cannot subscribe to list"
    end

    def notifications_list
      async_notifications_list.sync
    end

    def async_notifications_list
      Promise.resolve(self)
    end

    def subscription_status(user)
      async_subscription_status(user).sync
    end

    # Public: Async version of subscription_status.
    #
    # user - The User to check.
    #
    # Returns a Promise.
    def async_subscription_status(user)
      Promise.resolve(GitHub.newsies.subscription_status(user, notifications_list))
    end

  end
end
