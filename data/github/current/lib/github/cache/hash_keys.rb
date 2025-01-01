# typed: true
# frozen_string_literal: true

require "encoding_fixer"

module GitHub
  module Cache

    # Mixin for truncating and hashing long keys.
    module HashKeys
      extend T::Helpers
      requires_ancestor { ICacheConfig }

      KEY_LENGTH  = 250 # memcache key length
      HASH_LENGTH = 64 # length of hash suffix

      BAD_CHARS = %r{[^\x21-\x7E]}  # key must be only printable, low-ASCII characters

      def delete(key)
        super fix_key(key)
      end

      def async_delete(key)
        super fix_key(key)
      end

      def get(key, raw = false)
        key = fix_key(key)
        fix_read_value key, super(key, raw)
      end

      def async_get(key, raw = false)
        orig_key = key
        key = fix_key(key)
        super(key, raw).then do |response|
          next response unless response.exist?

          new_value = fix_read_value(key, response.value)
          ::GitHub::Cache::FakeResponse.new(key: orig_key, value: new_value, exists: true)
        end
      end

      def get_multi(keys, raw = false)
        key_map = Hash[keys.map { |k| [fix_key(k), k] }]
        results = super key_map.keys, raw

        Hash[results.map do |k, v|
          key = key_map.fetch(k)
          [key, fix_read_value(key, v)]
        end]
      end

      def async_get_multi(keys, raw = false)
        key_map = Hash[keys.map { |k| [fix_key(k), k] }]
        results = super key_map.keys, raw

        results.then do |resolved_results|
          Hash[resolved_results.map do |k, v|
            key = key_map.fetch(k)
            [key, fix_read_value(key, v)]
          end]
        end
      end

      def set(key, value, ttl = 0, raw = false)
        super fix_key(key), fix_write_value(key, value), ttl, raw
      end

      def async_set(key, value, ttl = 0, raw = false)
        Promise.resolve(value).then do |resolved_value|
          super fix_key(key), fix_write_value(key, resolved_value), ttl, raw
        end
      end

      def add(key, value, ttl = 0, raw = false)
        super fix_key(key), value, ttl, raw
      end

      def async_add(key, value, ttl = 0, raw = false)
        super fix_key(key), value, ttl, raw
      end

      def incr(key, value = 1)
        super fix_key(key), value
      end

      def async_incr(key, value = 1)
        super fix_key(key), value
      end

      def decr(key, value = 1)
        super fix_key(key), value
      end

      def async_decr(key, value = 1)
        super fix_key(key), value
      end

      # Internal: Fixes the key to stop problems
      #
      # 1. "Cleans" the key
      # 2. Truncates too-long key
      #
      # Returns a String key
      def fix_key(key)
        truncate(clean(key))
      end

      # Internal: Truncates key. Keys > KEY_LENGTH bytes are truncated at
      # KEY_LENGTH and a SHA256 hash of the full key is placed at KEY_LENGTH -
      # HASH_LENGTH. All keys are forced into the binary encoding.
      # Returns key if < KEY_LENGTH, otherwise a truncated copy.
      def truncate(key)
        max = KEY_LENGTH - (prefix_key ? T.must(prefix_key).length : 0)
        limit = max - HASH_LENGTH

        return key if key.bytesize <= max

        truncated = key.byteslice(0, limit)
        truncated.force_encoding(::Encoding::BINARY)
        truncated << Digest::SHA256.hexdigest(key)
      end

      # Internal: Cleans a key
      #
      # Any key containing bad characters is simply SHA256 hashed.
      # Other keys are left alone.
      #
      # Returns clean String key
      def clean(key)
        return key unless key
        return key if key.valid_encoding? && key !~ BAD_CHARS

        Digest::SHA256.hexdigest(key)
      end

      private

      def fix_write_value(key, value)
        return value if key =~ /gitrpc/
        return value if key =~ /gpgverify_cache/
        ::EncodingFixer::Write.new({ stats_key: "hash_keys", extended_data: key }).fix(value)
      end

      def fix_read_value(key, value)
        return value if key =~ /gitrpc/
        return value if key =~ /gpgverify_cache/
        ::EncodingFixer::Read.new({ stats_key: "hash_keys", extended_data: key }).fix(value)
      end
    end
  end
end
