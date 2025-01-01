# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    module DisableWrite
      extend T::Helpers
      requires_ancestor { GitHub::Cache::ICache }
      requires_ancestor { GitHub::Cache::IAsyncCache }
      include Kernel

      def set(key, value, ttl = 0, raw = false)
        if disable_write
          return value
        end

        super
      end

      def async_set(key, value, ttl = 0, raw = false)
        Promise.resolve(value).then do |resolved_value|
          if disable_write
            ::GitHub::Cache::FakeResponse.new(key: key, value: resolved_value, stored: true)
          else
            super
          end
        end
      end

      def async_add(key, value, ttl = 0, raw = false)
        Promise.resolve(value).then do |resolved_value|
          if disable_write
            ::GitHub::Cache::FakeResponse.new(key: key, value: resolved_value, stored: true)
          else
            super
          end
        end
      end

      def incr(key, value = 1)
        if disable_write
          return get(key).to_i + value
        end
        super
      end

      def async_incr(key, value = 1)
        if disable_write
          async_get(key).then do |response|
            next response unless response.exist?
            new_value = response.value.to_i + value
            ::GitHub::Cache::FakeResponse.new(key: key, value: new_value, stored: true)
          end
        else
          super
        end
      end

      def decr(key, value = 1)
        if disable_write
          return get(key).to_i - value
        end
        super
      end

      def async_decr(key, value = 1)
        if disable_write
          async_get(key).then do |response|
            next response unless response.exist?
            new_value = response.value.to_i - value
            ::GitHub::Cache::FakeResponse.new(key: key, value: new_value, stored: true)
          end
        else
          super
        end
      end

      def delete(key)
        if disable_write
          return get(key)
        end
        super
      end

      def async_delete(key)
        if disable_write
          async_get(key)
        else
          super
        end
      end

      def disable_write
        if block_given?
          @disable_write.tap do |old_value|
            @disable_write = true
            begin
              yield
            ensure
              @disable_write = old_value
            end
          end

        else
          @disable_write
        end
      end
    end
  end
end
