# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    # Mixin for disallowing long TTLs. TTLs longer than 30 days are interpreted
    # by the server as being an epoch timestamp. This ambiguity is confusing for
    # callers. Since data won't persist this long in our memcache deployment
    # anyway, we disallow long TTLs explicitly.
    module LongTTL
      include Kernel

      # Maximum TTL that memcached will treat as an offset from the current
      # time. Larger values will be treated as epoch timestamps.
      # https://github.com/memcached/memcached/blob/554b56687a19300a75ec24184746b5512580c819/doc/protocol.txt#L82-L90
      MAX_OFFSET_TTL = 60 * 60 * 24 * 30

      def set(key, value, ttl = 0, raw = false)
        enforce_ttl_limit(ttl)
        super
      end

      def async_set(key, value, ttl = 0, raw = false)
        enforce_ttl_limit(ttl)
        super
      end

      def add(key, value, ttl = 0, raw = false)
        enforce_ttl_limit(ttl)
        super
      end

      def async_add(key, value, ttl = 0, raw = false)
        enforce_ttl_limit(ttl)
        super
      end

      private

      # Raise ArgumentError on excessive TTLs.
      #
      # Returns nothing.
      def enforce_ttl_limit(ttl)
        if ttl.to_i > MAX_OFFSET_TTL
          raise ArgumentError, "memcache TTL #{ttl} exceeds max of #{MAX_OFFSET_TTL}"
        end
      end
    end
  end
end
