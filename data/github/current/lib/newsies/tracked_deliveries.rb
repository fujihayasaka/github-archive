# typed: false
# frozen_string_literal: true

require "set"

module Newsies
  # Public: Responsible for making sure a handler does not deliver a
  # notification to a user more than once.  A store is used to actually fetch
  # and save the saved handlers for a user.  Interactions with a store are
  # designed around bulk fetches and saves.  A store can preload handlers for
  # a group of users at once, and also save them after delivery.
  class TrackedDeliveries
    attr_reader :store, :unsaved

    # Public: Initializes a new TrackedDeliveries object.
    #
    # store     - A store object that implements #[], #preload, and #save.
    #             Only #[] is required, so a Hash works just fine.
    # *user_ids - One or more Integer User IDs that the store should preload.
    def initialize(store, *user_ids)
      @unsaved = {}
      @store = store || {}
      reset_for(*user_ids)
    end

    # Public: Gets the delivered handlers for a given user ID.  Ideally the
    # user_id was passed in the initializer and alreaddy preloaded.
    #
    # user_id - Integer User ID.
    #
    # Returns an Array of String handlers.
    def handlers(user_id)
      @store[user_id] || []
    end

    # Public: Gets the reason that the user was delivered with the handler.
    #
    # user_id - Integer User ID.
    # handler - String handler key.
    #
    # Returns a String reason, or nil.
    def reason(user_id, handler)
      if @store.respond_to?(:reason)
        @store.reason(user_id, handler)
      end
    end

    # Public: Temporarily store the handler for the user id.  This is held
    # internally and saved through #save.
    #
    # user_id - Integer User ID.
    # handler - String handler key.
    # reason  - String reason for the delivery.
    #
    # Returns nothing.
    def set_handler(user_id, handler, reason)
      (@unsaved[user_id] ||= []) << [handler, reason]
    end

    # Public: Saves the unsaved handlers from #set_handler in the store.  If
    # the store doesn't implement #save, then nothing happens.
    #
    # Returns nothing.
    def save
      @store.save(@unsaved) if @store.respond_to?(:save)
      @unsaved.clear
    end

    def reset_for(*user_ids)
      @store.preload(user_ids) if @store.respond_to?(:preload)
    end
  end
end
