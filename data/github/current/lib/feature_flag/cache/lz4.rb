# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Cache
    module LZ4
      extend T::Sig
      extend T::Helpers
      requires_ancestor { IMemcachedClient }
      include Kernel

      MAX_ATTEMPT_CACHE_SIZE = 10_000_000
      MAX_UNCOMPRESSED_SIZE  = 500_000
      LZ4_HEADER             = :lz4

      sig { params(key: String, raw: T::Boolean).returns(T.untyped) }
      def get(key, raw = false)
        return super if raw
        decompress_value(key, super)
      end

      sig { params(keys: T::Array[String], raw: T::Boolean).returns(T::Hash[String, T.untyped]) }
      def get_multi(keys, raw = false)
        hash = {}
        super(keys, raw).each do |key, value|
          hash[key] = decompress_value(key, value)
        end
        hash
      end

      sig { params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T.untyped) }
      def set(key, value, ttl = 0, raw = false)
        value, raw, success = compress_value(key, value, raw)
        super(key, value, ttl, raw) if success
      end

      sig { params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T.untyped) }
      def add(key, value, ttl = 0, raw = false)
        value, raw, success = compress_value(key, value, raw)
        super(key, value, ttl, raw) if success
      end

      private

      sig { params(key: String, value: T.untyped, raw: T::Boolean).returns([T.untyped, T::Boolean, T::Boolean]) }
      def compress_value(key, value, raw)
        if !raw
          value = GitHub::Cache::Codec.pack(value)

          if value.bytesize > MAX_ATTEMPT_CACHE_SIZE
            return [nil, true, false]
          end

          if value.bytesize > MAX_UNCOMPRESSED_SIZE
            begin
              value = GitHub::Cache::Codec.pack([LZ4_HEADER, ::LZ4::compress(value)])
            rescue Zlib::DataError => e
              Failbot.report!(e, app: "feature-flag-cache-lz4")
              delete(key)
              return [nil, true, false]
            end
          end
        end

        [value, true, true]
      end

      sig { params(key: String, value: T.untyped).returns(T.untyped) }
      def decompress_value(key, value)
        return value unless value.is_a?(Array) && value[0] == LZ4_HEADER
        begin
          GitHub::Cache::Codec.unpack(::LZ4::decompress(value[1]))
        rescue Zlib::BufError => e
          Failbot.report!(e, app: "feature-flag-cache-lz4")
          delete(key)
          nil
        rescue => boom # rubocop:todo Lint/GenericRescue
          raise unless GitHub::Cache.unmarshal_error?(boom)
          delete(key)
          nil
        end
      end
    end
  end
end
