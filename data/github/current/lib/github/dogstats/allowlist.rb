# typed: true
# frozen_string_literal: true

require "github/dogstats"
require "concurrent/map"

# Dogstats client that only sends stats that have been allowlisted.
# While this implementation is generic, it's primarily used in GitHub Enterprise
# environments where we want to limit the metrics to control the volume at the source.
#
#     dogstats = GitHub::Dogstats::Allowlist.new(%w(
#       pages.failure
#       unicorn.{browser,ajax}.requests_per_second
#       allowlisted.*
#     ), "localhost", 8125)
#
#     dogstats.increment("allowlisted.key")
#     dogstats.increment("not.allowlisted") # ignored
#
# The allowlist is an array of strings. Expansion (`{a,b}`) and wildcards (`*`)
# are supported. `*` will match any character, including a period.
module GitHub
  class Dogstats::Allowlist < Dogstats
    def initialize(allowlist = [], host = nil, port = nil, allowlist_cache_size: 0, **kwargs)
      super(host, port, **kwargs)
      @allowlist = allowlist
      @allowlist_cache = Concurrent::Map.new
      @allowlist_cache_lock = Mutex.new
      @allowlist_cache_size = allowlist_cache_size
    end

    attr_reader :allowlist_cache_size

    private

    # Override the internal send_stats method that all metric methods use
    def send_stats(stat, delta, type, opts = {})
      if allowlisted?(stat)
        super(stat, delta, type, opts)
      end
      # If not allowlisted, do nothing - metric is blocked
    end

    def allowlisted?(stat)
      stat = stat.to_s
      cached = @allowlist_cache[stat]
      return cached unless cached.nil?

      allowed = @allowlist.any? { |pattern| File.fnmatch(pattern, stat, File::FNM_EXTGLOB) }

      # The cache key is only the metric name. If the decision ever depends on tags or options,
      # add them to the key or remove the cache. Once the cache is full, keep the existing entries
      # instead of evicting: evicting can make a repeating set of names miss the cache every time.
      cache_allowlist_result(stat, allowed) if @allowlist_cache.size < @allowlist_cache_size
      allowed
    end

    # Check the size and add the name under one lock, so threads that miss at the same time can't
    # grow the cache past its size or log "cache full" more than once. Log after unlocking so other
    # threads don't wait on the logger.
    def cache_allowlist_result(stat, allowed)
      filled = @allowlist_cache_lock.synchronize do
        next false if @allowlist_cache.size >= @allowlist_cache_size

        @allowlist_cache[stat] = allowed
        @allowlist_cache.size == @allowlist_cache_size
      end
      return unless filled

      GitHub.logger.info("GitHub::Dogstats::Allowlist cache full", {
        "gh.dogstats.allowlist_cache_size" => @allowlist_cache_size,
      })
    end
  end
end
