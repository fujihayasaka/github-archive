# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  module Util
    # Emulates Dalli's basic cache interface using a local process hash to back
    # values. This cache implementation is used by GitRPC::Client when no
    # explicit Dalli object is provided making it possible to use GitRPC in
    # environments that don't have memcache.
    #
    # In addition, most GitRPC::Client tests use this as a backing store to
    # verify caching logic.
    #
    # See GitRPC::Cache for method documentation.
    class HashCache
      attr_reader :hash

      def initialize(hash = {})
        @hash = hash
      end

      def get(key, options = {})
        if val = @hash[key]
          val = Marshal.load(val) if !options[:raw]
          val
        end
      end

      def set(key, val, ttl = nil, options = {})
        val = Marshal.dump(val) if !options[:raw]
        if @track_sets
          @tracked_sets << key
        end
        @hash[key] = val
      end

      def exist?(key)
        !@hash[key].nil?
      end

      def fetch(key, ttl = nil, options = {})
        if @hash[key].nil?
          val = yield
          set(key, val, ttl, options)
          val
        else
          get(key, options)
        end
      end

      def get_multi(*keys)
        options = keys.last.is_a?(Hash) ? keys.pop : {}
        keys = keys.flatten & @hash.keys  # only get values for already-cached keys
        hash = {}
        keys.each { |key| hash[key] = get(key, options) }
        hash
      end

      def delete(key)
        @hash.delete(key)
      end

      def track_sets
        @track_sets = true
        @tracked_sets = []
        yield
        @track_sets = false
        @tracked_sets
      end

      class Lazy
        attr_reader :hash

        def initialize(hash = {})
          @hash = hash
        end

        def set(key, val, *)
        end

        def get(*)
        end

        def get_multi(*)
          {}
        end

        def fetch
          yield
        end
      end
    end
  end
end
