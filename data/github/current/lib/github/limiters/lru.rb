# typed: false
# frozen_string_literal: true

module GitHub
  module Limiters
    class LRU < GitHub::Limiter
      def initialize(name, max:, window: 60, size: 500, &block)
        super(name)

        @cache = LruRedux::TTL::Cache.new(size, window)
        @block = block
        @max   = max
      end

      def start(request)
        (@max > 0 && val(key(request)) <= @max) ? OK : LIMITED
      end

      def finish(request)
        incr(key(request), cost(request))
      end

      def cancel(request)
        decr(key(request), cost(request))
      end

      def timeout(request)
        finish(request, nil)
      end

      protected

      def key(request)
        @block.call(request)
      end

      def cost(request)
        1
      end

      def incr(k, v)
        @cache[k] = (@cache[k] || 0) + v
      end

      def decr(k, v)
        @cache[k] = (@cache[k] || 0) - v
      end

      def val(k)
        @cache[k] || 0
      end
    end
  end
end
