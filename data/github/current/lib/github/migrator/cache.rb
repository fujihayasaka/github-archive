# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class Cache
      DEFAULT_CACHE_SIZE = 100_000

      def self.null
        Null.new
      end

      def initialize(*args)
        max_size, _ = args
        max_size ||= DEFAULT_CACHE_SIZE

        @max_size = max_size
        @data = {}
      end

      def getset(key)
        found = T.let(true, T::Boolean)
        value = @data.delete(key) { found = false }
        if found
          @data[key] = value
        else
          value = yield
          result = @data[key] = value if value
          @data.shift if @data.length > @max_size
          result
        end
      end

      def clear
        @data.clear
      end

      class Null
        def getset(*)
          yield
        end
      end
    end
  end
end
