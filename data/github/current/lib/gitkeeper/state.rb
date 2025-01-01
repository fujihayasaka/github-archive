# typed: true
# frozen_string_literal: true

module Gitkeeper
  module State
    TTL = 10.minutes.freeze
    STATS_KEY = "gitkeeper.cache.state"

    def cache_key(repo)
      "repo-#{repo.id}:gitkeeper:state:#{repo.updated_at.to_i}"
    end

    def set_cache_key(repo)
      GitHub.cache.fetch(cache_key(repo), ttl: TTL) { "pass" }
    end

    def good_state?(repo)
      start = GitHub::Dogstats.monotonic_time
      cache_exist = GitHub.cache.exist?(cache_key(repo))
      cache_state = cache_exist ? "hit" : "miss"
      GitHub.dogstats.timing_since(STATS_KEY, start, tags: ["type:#{cache_state}"])
      cache_exist
    end

    extend self
  end
end
