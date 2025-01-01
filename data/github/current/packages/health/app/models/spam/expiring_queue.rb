# typed: true
# frozen_string_literal: true

module Spam
  class ExpiringQueue
    attr_accessor :prefix, :ttl, :store

    def initialize(prefix, ttl)
      @prefix    = prefix
      @ttl       = ttl
      @store     = Spam::Kv.store
    end

    def item_key(item)
      @prefix + item.downcase
    end

    # Clear an existing item
    #
    # item - String to remove
    #
    # Returns nothing.
    def clear(item)
      key = item_key(item)
      @store.del(key)
    end

    # Set an auto-expiring value in the keyval store for this item.
    #
    # item  - String to flag as tainted
    # value - Value to store; for Users, typically the `id` of the last User
    #         with `item` as its login
    #
    # Returns nothing.
    def set(item, value = 1)
      set_with_timeout(item_key(item), value)
    end

    # Return the item's value if it is still on the queue.
    #
    # item - String to check
    #
    # Returns the stored value if the key exists, and nil otherwise.
    def get(item)
      key = item_key(item)
      @store.get(key).value!
    end

    private

    # Set an auto-expiring value in the key-value store
    def set_with_timeout(key, value)
      @store.set(key, value.to_s, expires: @ttl.seconds.from_now)
    end
  end
end
