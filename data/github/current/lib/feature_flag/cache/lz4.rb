# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Cache
    module LZ4
      extend T::Helpers
      requires_ancestor { IMemcachedClient }
      include Kernel

      MAX_ATTEMPT_CACHE_SIZE = 10_000_000
      MAX_UNCOMPRESSED_SIZE  = 1000
      LZ4_HEADER             = :lz4

      sig { params(key: String, raw: T::Boolean).returns(T.untyped) }
      def get(key, raw = false)
        return super if raw

        decompress_value(key, super)
      end

      sig { params(keys: T::Array[String], raw: T::Boolean).returns(T::Hash[String, T.untyped]) }
      def get_multi(keys, raw = false)
        return super if raw

        hash = {}
        super(keys, raw).each do |key, value|
          hash[key] = decompress_value(key, value)
        end
        hash
      end

      sig { params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T.untyped) }
      def set(key, value, ttl = 0, raw = false)
        return super if raw

        value, raw, success = compress_value(key, value)
        super(key, value, ttl, raw) if success
      end

      sig { params(key: String, value: T.untyped, ttl: Integer, raw: T::Boolean).returns(T.untyped) }
      def add(key, value, ttl = 0, raw = false)
        return super if raw

        value, raw, success = compress_value(key, value)
        super(key, value, ttl, raw) if success
      end

      private

      sig { params(key: String, value: T.untyped).returns([T.untyped, T::Boolean, T::Boolean]) }
      def compress_value(key, value)
        value = FeatureFlag::Cache::MsgPack.pack(value)

        if value.bytesize > MAX_ATTEMPT_CACHE_SIZE
          GitHub.dogstats.increment("gh.feature_flag.cache.max_attempt_size_exceeded.count")
          return [nil, true, false]
        end

        if value.bytesize > MAX_UNCOMPRESSED_SIZE
          begin
            value = FeatureFlag::Cache::MsgPack.pack([LZ4_HEADER, ::LZ4::compress(value)])
          rescue LZ4Error => e
            Failbot.report!(e, app: "feature-flag-cache-lz4")
            delete(key)
            return [nil, true, false]
          end
        end

        [value, true, true]
      end

      sig { params(key: String, value: T.untyped).returns(T.untyped) }
      def decompress_value(key, value)
        return value unless value.is_a?(Array) && value[0] == LZ4_HEADER
        begin
          FeatureFlag::Cache::MsgPack.unpack(::LZ4::decompress(value[1]))
        rescue LZ4Error => e
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
