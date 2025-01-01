# typed: strict
# frozen_string_literal: true

require "explore_feed/feeds/kv"

module Conduit
  class KVBackedCache
    MAX_BODY_SIZE = T.let(64.kilobytes.freeze, Integer)

    # Ideally this would be moved into a more general conduit namespace
    # so that's not related specifically to a KVBackedCache but any role-player e.g.
    # an in memory cache, or a redis cache, or whatever else may come in the future.
    # For now it is low cost to keep it here.
    class CacheUnavailableError < StandardError; end

    # This error however is specific to the KVBackedCache, so it makes sense for it to live here.
    class CacheableBodySizeExceededError < StandardError; end

    # Attempts to get the contents of the cache for a user, if no cached value is available,
    # evaluates the result of the block and attempts to cache it, finally returning that result.
    #
    # Note that this is best effort and if the KV store is unavailable on get, it will evaluate the block
    # and if unavailable on set, will return the value uncached. In each case an error will be reported
    # to failbot.
    #
    # A consideration for the future would be returning a type with the result and whether
    # the cache operations were successful, such that the caller can take action. Currently,
    # the caller won't take any action, so implementing this is extra maintenance.
    sig { params(user: User, blk: T.proc.returns(String)).returns(String) }
    def self.get_or_set_for(user, &blk)
      cache_key = cache_key_for(user)

      # Try to get the contents of the cache.
      # If there is an error then report and treat cache contents as if they weren't found.
      cache_contents = Feeds::KV.store.get(cache_key).value do |error|
        Failbot.report(error)
        nil
      end

      # If we got something from the cache report a hit and return the contents.
      unless cache_contents.nil?
        GitHub.dogstats.increment("conduit_feed.cache.hit")
        return cache_contents
      end

      # Otherwise report a cache miss and evaluate the block
      GitHub.dogstats.increment("conduit_feed.cache.miss")
      computed_result = yield

      # If the result is larger than the KV cache can hold, report an error
      # and return the result.
      if computed_result.bytesize >= MAX_BODY_SIZE
        GitHub.dogstats.increment("conduit_feed.cache.exceeded")
        Failbot.report(CacheableBodySizeExceededError.new, bytesize: computed_result.bytesize)

        return computed_result
      end

      # Otherwise, store the result in the cache.
      ActiveRecord::Base.connected_to(role: :writing) do
        # If there is an error then ensure we report it, but don't re-raise
        begin
          Feeds::KV.store.set(cache_key, computed_result, expires: 10.minutes.from_now)
        rescue GitHub::KV::UnavailableError => e
          Failbot.report(e)
        end
      end

      computed_result
    end

    # Invalidates the contents of the cache for this user.
    #
    # If the KV store is unavailable, will raise a CacheUnavailableError as the caller should know
    # that cache eviction has failed.
    sig { params(user: User).void }
    def self.invalidate_for(user)
      Feeds::KV.store.del cache_key_for(user)
    rescue GitHub::KV::UnavailableError
      raise Conduit::KVBackedCache::CacheUnavailableError.new
    end

    sig { params(user: User).returns(String) }
    private_class_method def self.cache_key_for(user)
      "conduit_feed.#{user.id}"
    end
  end
end
