# typed: true
# frozen_string_literal: true

module Newsies
  # Responsible for preloading and retrieving notification delivery audit data.
  class NotificationDeliveryStore
    attr_reader :list_id, :thread_key, :comment_key

    # list_id    - The Integer List ID.
    # thread_key - The String Thread key.
    # comment_id - The Integer Comment ID.
    def initialize(list, thread, comment)
      @list_id = Newsies::List.to_id(list)
      @thread_key = Newsies::Thread.to_key(thread)
      @comment_key = Newsies::Comment.to_key(comment)
      @preloaded = nil
    end

    # Public: Gets the preloaded handlers that a User has been notified with.
    #
    # user_id - Integer User ID.
    #
    # Returns an Array of String handler keys.
    def handlers(user_id)
      if hash = @preloaded[user_id]
        hash.keys
      end
    end

    alias [] handlers

    # Public: Gets the reason that a User received the delivery.
    #
    # user_id - The Integer User ID.
    # handler - The String Handler key.
    #
    # Returns the String reason, or nil if the user has not been notified
    # through this handler.
    def reason(user_id, handler)
      if hash = @preloaded[user_id]
        hash[handler.to_s]
      end
    end

    # Public: Loads previous deliveries for the given user IDs in the given
    # Thread.
    #
    # user_ids   - Array of Integer User IDs.
    #
    # Returns a Hash of Integer User ID keys and Hash handler details.
    def preload(user_ids)
      @preloaded = {}
      user_ids = user_ids.uniq
      user_ids.sort!
      user_ids.in_groups_of(500, false) do |ids|
        @preloaded.update NotificationDelivery.handler_data(@list_id, @thread_key, @comment_key, ids)
      end
      @preloaded
    end

    # Public: Performs a batch save of the delivered notifications.
    #
    # unsaved - A Hash of Integer User ID keys and Hash handler details.
    #
    # Returns nothing.
    def save(unsaved)
      NotificationDelivery.batch_create_from_handler_data(@list_id, @thread_key, @comment_key, unsaved)
    end
  end
end
