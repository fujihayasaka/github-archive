# typed: true
# frozen_string_literal: true

module UserRanked
  class Cache
    TTL = 8.hours
    CACHE_LIMIT = 1000 # We only cache the first 1000 ranked ids.

    # Public: Use this access method to fetch an ordered list of ids ranked for
    # a given user.
    #
    # ranked_class_name - String name of the type (e.g. "Team", "Repository")
    # user - A User. The ranking is applied from this user's perspective.
    # opts - A hash of other fields that should be included in the cache key.
    #        Use sparingly to maximize cache hit ratio.
    #
    def self.fetch_ranked_ids(ranked_class_name, user, opts = {}, &block_to_calculate)
      new(ranked_class_name, user, opts, &block_to_calculate).fetch_ranked_ids
    end

    def initialize(ranked_class_name, user, opts = {}, &block_to_calculate)
      @ranked_class_name = ranked_class_name
      @user = user
      @opts = opts
      @block_to_calculate = block_to_calculate
    end

    def fetch_ranked_ids
      if cached_val = GitHub.kv.get(cache_key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        tags = ["type:hit"]
        results = cached_val.split(",").map(&:to_i)
      else
        tags = ["type:miss"]
        results = block_to_calculate&.call.first(CACHE_LIMIT) || []

        ActiveRecord::Base.connected_to(role: :writing) do
          GitHub.kv.set(cache_key, results.join(","), expires: TTL.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
        end
      end

      GitHub.dogstats.count("user_ranked_cache.#{ranked_class_name}", 1, tags: tags)
      results
    rescue GitHub::KV::KeyLengthError,
      GitHub::KV::ValueLengthError,
      GitHub::KV::InvalidValueError,
      GitHub::KV::UnavailableError => e
      Failbot.report(e)
      results
    end

    private

    attr_reader :block_to_calculate, :ranked_class_name, :user, :opts

    def cache_key
      if opts.present?
        "user-ranked:#{ranked_class_name}:#{user.id}:#{opts.sort.to_h.values.join(":")}"
      else
        "user-ranked:#{ranked_class_name}:#{user.id}"
      end
    end

    def stats_key
      "user-ranked:#{ranked_class_name}:cache"
    end
  end
end
