# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    # Mixin for configuring all cache gets to register as misses. This is
    # typically set at the beginning of a web request to cause all caches to be
    # refreshed to newly generated values.
    module Skip
      extend T::Helpers
      requires_ancestor { ICache }
      requires_ancestor { IAsyncCache }
      attr_accessor :skip

      def get(key, raw = false)
        if skip
          delete(key)
          return nil
        end

        super
      end

      def async_get(key, raw = false)
        if skip
          return async_delete(key).then do
            # inject a fake but compatible "does not exist" response
            ::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false)
          end
        end

        super
      end

      def get_multi(keys, raw = false)
        if skip
          keys.each { |key| delete(key) }
          return {}
        end

        super
      end

      def async_get_multi(keys, raw = false)
        if skip
          deletes = keys.map { |key| async_delete(key) }
          return Promise.all(deletes).then do
            {}
          end
        end

        super
      end
    end
  end
end
