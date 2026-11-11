# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class Cache < Platform::Loader
      def self.fetch(key, ttl: 0)
        raise Errors::Internal, "must pass block to compute value" unless block_given?

        load(key).then do |cached_value|
          if cached_value
            cached_value
          else
            Promise.resolve(yield).then do |computed_value|
              GitHub.cache.set(key, computed_value, ttl)
              computed_value
            end
          end
        end
      end

      def self.load(key)
        self.for.load(key)
      end

      def fetch(keys)
        GitHub.cache.get_multi(keys)
      end
    end
  end
end
