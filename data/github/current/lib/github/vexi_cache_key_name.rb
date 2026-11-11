# typed: true
# frozen_string_literal: true

# Allows RemoteCache cache key names to be used as Vexi actors.
module GitHub
  class VexiCacheKeyName
    include GitHub::VexiActor

    def initialize(cache_key_name)
      @cache_key_name = cache_key_name
    end

    def ==(other)
      self.class == other.class && vexi_id == other.vexi_id
    end
    alias_method :eql?, :==

    def vexi_id
      "CacheKeyName:#{@cache_key_name}"
    end
  end
end
