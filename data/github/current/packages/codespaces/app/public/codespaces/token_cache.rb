# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class TokenCache
    def self.read_codespace_cascade_token(owner_id:, guid:)
      cache_key = codespace_cascade_token_key(owner_id: owner_id, guid: guid)
      read(cache_key)
    end

    def self.write_codespace_cascade_token(owner_id:, guid:, token:, expiration:)
      expires_at = begin
        Time.at(expiration)
      rescue TypeError
        nil
      end
      if expires_at
        expires_in = ((expires_at - Time.now) / 1.hour).floor
        cache_key = codespace_cascade_token_key(owner_id: owner_id, guid: guid)
        write(data: token, cache_key: cache_key, expires_in: expires_in.hours) if expires_in > 0
      end
    end

    def self.codespace_cascade_token_key(owner_id:, guid:)
      generate_key(owner_id, guid, type: "codespace_cascade")
    end

    # Public: Class method that writes to cache and optionally encrypts value
    #
    # data - String; Value to store in cache.
    # expires_in - duration; When the cache value should expire.
    # cache_key - String; Key to store value in cache.
    # encrypted - Boolean; Whether the value should be encrypted.
    # encryptor - RbNaCl::SimpleBox instance; The encryptor to use to encrypt the value if `encrypted` is `true`.
    def self.write(data:, expires_in:, cache_key:, encrypted: false, encryptor: nil)
      cache_value = encrypted && encryptor ? encryptor.encrypt(data) : data

      # To avoid fetching tokens from the cache that are immediately about to expire, calculate
      # a buffer for the cache expiration. This is 10% of the life of the token or 5 minutes,
      # whichever is shorter.
      cache_expiry_buffer = [(expires_in * 0.10).floor, 5.minutes].min

      ActiveRecord::Base.connected_to(role: :writing) do
        Codespaces::Kv.store.set(cache_key, cache_value, expires: (expires_in - cache_expiry_buffer).from_now)
      end
      data
    end

    # Public: Class method that reads cache and optionally decrypts value
    #
    # cache_key - String; Key to fetch value from cache
    # encrypted - Boolean; Whether the value is encrypted
    # encryptor - RbNaCl::SimpleBox instance; The encryptor to use to decrypt the value if it is encrypted.
    def self.read(cache_key, encrypted: false, encryptor: nil)
      data = Codespaces::Kv.store.get(cache_key).value { nil }

      return nil unless data
      return data unless encrypted && encryptor

      begin
        encryptor.decrypt(data)
      rescue RbNaCl::CryptoError
        # Failed to decrypt the value. Attempt to use the data as-is in case the value is usable but log to DataDog so we can investigate why decryption isn't working.
        GitHub.dogstats.increment("codespaces.token_cache.read.decrypt_error", tags: ["cache_key:#{cache_key}"])
        data
      end
    end

    def self.generate_key(*key_segments, type:)
      "codespaces.token.#{type}.#{Digest::SHA256.hexdigest(key_segments.join)}"
    end
  end
end
