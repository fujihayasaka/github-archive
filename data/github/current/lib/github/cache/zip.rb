# typed: false
# frozen_string_literal: true

require "zlib"

module GitHub
  module Cache
    module Zip
      MAX_ATTEMPT_CACHE_SIZE = 10_000_000
      MAX_UNZIPPED_SIZE      = 500_000
      ZIP_HEADER             = :z

      def set(key, value, ttl = 0, raw = false)
        if attempt_cache?(value)
          value, raw, success = zip_value(key, value, raw)
          super(key, value, ttl, raw) if success
        end
      end

      def async_set(key, value, ttl = 0, raw = false)
        Promise.resolve(value).then do |resolved_value|
          response = FakeResponse.new(key: key, value: resolved_value, stored: false)

          if attempt_cache?(resolved_value)
            value, raw, success = zip_value(key, resolved_value, raw)
            response = super(key, value, ttl, raw) if success
          end

          response
        end
      end

      def add(key, value, ttl = 0, raw = false)
        if attempt_cache?(value)
          value, raw, success = zip_value(key, value, raw)
          super(key, value, ttl, raw) if success
        end
      end

      def async_add(key, value, ttl = 0, raw = false)
        Promise.resolve(value).then do |resolved_value|
          response = FakeResponse.new(key: key, value: resolved_value, stored: false)

          if attempt_cache?(resolved_value)
            value, raw, success = zip_value(key, resolved_value, raw)
            response = super(key, value, ttl, raw) if success
          end

          response
        end
      end

      def get_multi(keys, raw = false)
        hash = {}
        super(keys, raw).each do |key, value|
          hash[key] = unzip_value(key, value)
        end
        hash
      end

      def async_get_multi(keys, raw = false)
        super(keys, raw).then do |results|
          hash = {}
          results.each do |key, value|
            hash[key] = unzip_value(key, value)
          end
          hash
        end
      end

      def get(key, raw = false)
        return super if raw
        unzip_value(key, super)
      end

      def async_get(key, raw = false)
        return super if raw
        super.then do |response|
          next response unless response.exist?
          value = unzip_value(key, response.value)
          ::GitHub::Cache::FakeResponse.new(key: key, value: value, exists: true)
        end
      end

      private

      def zip_value(key, value, raw)
        if !raw
          value = GitHub::Cache::Codec.pack(value)

          if value.bytesize > MAX_ATTEMPT_CACHE_SIZE
            return [nil, true, false]
          end

          if value.bytesize > MAX_UNZIPPED_SIZE
            begin
              value = GitHub::Cache::Codec.pack([ZIP_HEADER, Zlib::Deflate.deflate(value)])
            rescue Zlib::DataError => e
              Failbot.report!(e, app: "github-zlib-cache")
              delete(key)
              return [nil, true, false]
            end
          end
        end

        [value, true, true]
      end

      def unzip_value(key, value)
        return value unless value.is_a?(Array) && value[0] == ZIP_HEADER
        begin
          GitHub::Cache::Codec.unpack(Zlib::Inflate.inflate(value[1]))
        rescue Zlib::BufError => e
          Failbot.report!(e, app: "github-zlib-cache")
          delete(key)
          nil
        rescue => boom # rubocop:todo Lint/GenericRescue
          raise unless GitHub::Cache.unmarshal_error?(boom)
          delete(key)
          nil
        end
      end

      def attempt_cache?(value)
        !value.respond_to?(:bytesize) || value.bytesize < MAX_ATTEMPT_CACHE_SIZE
      end
    end
  end
end
