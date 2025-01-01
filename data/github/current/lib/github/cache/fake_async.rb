# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    # Mixin that fakes _async versions of functions, by executing them immediately
    # but enclosing them in a resolved promise.
    module FakeAsync
      extend T::Helpers
      requires_ancestor { WithoutMixins }
      include IAsyncCache

      def async_get(key, raw = false)
        Promise.resolve.then do
          results = orig_get_multi([key], raw)
          value = results[key]
          exists = results.has_key?(key)

          FakeResponse.new(key: key, value: value, exists: exists)
        end
      end

      def async_get_multi(keys, raw = false)
        Promise.resolve.then do
          orig_get_multi(keys, raw)
        end
      end

      def async_set(key, value, ttl = 0, raw = false)
        Promise.resolve(value).then do |resolved_value|
          stored = !!orig_set(key, resolved_value, ttl, raw)
          FakeResponse.new(key: key, value: resolved_value, stored: stored)
        end
      end

      def async_add(key, value, ttl = 0, raw = false)
        Promise.resolve(value).then do |resolved_value|
          stored = !!orig_add(key, resolved_value, ttl, raw)
          FakeResponse.new(key: key, value: resolved_value, stored: stored)
        end
      end

      def async_incr(key, value = 1)
        Promise.resolve.then do
          FakeResponse.new(key: key, value: orig_incr(key, value), stored: true)
        end
      end

      def async_decr(key, value = 1)
        Promise.resolve.then do
          FakeResponse.new(key: key, value: orig_decr(key, value), stored: true)
        end
      end

      def async_delete(key, raw = false)
        Promise.resolve.then do
          orig_delete(key)
          FakeResponse.new(key: key, value: nil, stored: true)
        end
      end

      def async_exist?(key, options = nil)
        Promise.resolve.then do
          orig_exist?(key, options)
        end
      end
    end
  end
end
