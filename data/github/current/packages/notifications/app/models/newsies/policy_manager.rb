# typed: true
# frozen_string_literal: true

module Newsies
  class PolicyManager
    # A subset of the reasons returned by `reason_to_stop_delivery` that describe a situation in
    # which we should both skip notification delivery and subsequently delete all of user's
    # newsies data for a given list.
    REASONS_TO_PURGE_NEWSIES_DATA = [:newsies_disabled, :list_unreadable]

    # Filters out subscribers who are not authorized to receive a notification for the given thread and list
    # Will trigger cleanup if the reason a user is unauthorized is in REASONS_TO_PURGE_NEWSIES_DATA
    #
    # Returns a list of subscribers who may receive the notification
    def self.authorize_subscribers(list, thread, subscribers)
      user_ids_for_which_to_purge_data = []

      authorized_subscribers = subscribers.select do |subscriber|
        next false if subscriber.settings.nil?
        next false if subscriber.settings.user.suspended?

        if (reason = reason_to_stop_delivery?(list, thread, subscriber.user))
          if REASONS_TO_PURGE_NEWSIES_DATA.include?(reason)
            user_ids_for_which_to_purge_data << subscriber.user_id
          end
          next false
        end

        true
      end

      if user_ids_for_which_to_purge_data.present?
        subject = Notifications::Subject.new(type: list.class.name, id: list.id)
        Notifications::Subscriptions.async_delete_list_subscriptions_for_users(list: subject, user_ids: user_ids_for_which_to_purge_data)
      end

      authorized_subscribers
    end

    # Checks that a single user can receive notifications.
    #
    # list   - A notification list, e.g a Repository, Team etc.
    # thread - The object generating the notification (Issue, Commit, DiscussionPost, etc.)
    # user   - The User due to receive a notification.
    #
    # Returns Boolean
    def self.recipient_authorized?(list, thread, user)
      subscribers = GitHub.newsies.bulk_loaded_subscribers([Newsies::Subscriber.new(user.id)])
      authorize_subscribers(list, thread, subscribers).present?
    end

    # Checks to see if there is a reason the user should not get a delivery.
    #
    # list   - A Repository or a Team.
    # thread - The object generating the notification (Issue, Commit, DiscussionPost, etc.)
    # user   - The User due to receive a notification.
    #
    # Returns a Symbol (which is truthy) if the delivery should be stopped, false otherwise.
    def self.reason_to_stop_delivery?(list, thread, user)
      return :newsies_disabled unless user&.newsies_enabled?
      return :list_unreadable unless list_readable?(list, thread, user)
      return :thread_unreadable if thread.respond_to?(:readable_by?) && !thread.readable_by?(user)
      false
    end
    private_class_method :reason_to_stop_delivery?

    def self.list_readable?(list, thread, user)
      # This is a hack that overrides User#readable_by? which only returns
      # true if the list and the user are the same object. The user of a Gist is
      # treated as its list. From a notifications perspective, a user should
      # be able to read any other user.
      return true if thread.is_a?(Gist) && list.is_a?(User)

      # This is a hack that overrides `Repository#readable_by?` for private repositories,
      # when the notification thread is for a RepoInvite to that private repo. The
      # `list#readable_by?` will return `false` until the user has accepted the invite,
      # so it's a chicken-and-egg problem.
      return true if thread.is_a?(RepositoryInvitation) && list.is_a?(Repository) && thread.readable_by?(user)

      return true if list.is_a?(Repository) && list.resources.contents.readable_by?(user)

      list.readable_by?(user)
    end
    private_class_method :list_readable?
  end
end
