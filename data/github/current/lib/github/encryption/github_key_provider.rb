# typed: true
# frozen_string_literal: true

require_relative "encryption_errors"

module GitHub
  module Encryption
    class GitHubKeyProvider
      AES_SIZE = 256
      def initialize(table:, attribute:)
        @table = table
        @attribute = attribute
        # Ensure the table and attribute are valid symbols
        validate_salt!(table)
        validate_salt!(attribute)


        # load the keys from the environment
        keys = GitHub.encrypted_column_keying_material
        validate_keys_available!(keys)

        # split the keys into multiple individual keys
        keys = keys.split(";")

        # in the case that keys is empty (e.g "") the
        # array from split will be [ ] and the following
        # check catches that case
        validate_at_least_one_key!(keys)

        # decode the keys
        keys = keys.map do |k|
          begin
            key = Base64.strict_decode64(k)
            validate_key_length!(key)
            key
          rescue ArgumentError
            stat_validation_error("invalid_key_encoding")
            raise KeyEncodingError.new("Invalid key (stored in ENCRYPTED_COLUMN_KEYING_MATERIAL) encoding")
          end
        end

        current_encryption_key = GitHub.encrypted_column_current_encryption_key
        validate_current_encryption_key_available!(current_encryption_key)
        begin
          current_encryption_key = Base64.strict_decode64(current_encryption_key)
        rescue ArgumentError
          stat_validation_error("invalid_current_encryption_key_encoding")
          raise KeyEncodingError.new("Invalid key (stored in ENCRYPTED_COLUMN_CURRENT_ENCRYPTION_KEY) encoding")
        end
        validate_current_encryption_key_length!(current_encryption_key)
        validate_keys_contain_current_encryption_key!(keys, current_encryption_key)

        @keys = keys
        @current_encryption_key = current_encryption_key
        @salt = "#{table}_#{attribute}"
      end

      def encryption_key
        key_material = @current_encryption_key
        key, salt, anti_nonce_exhaustion_data = build_key(key_material)
        dummy_key = ActiveRecord::Encryption::Key.new(key_material)
        arkey = ActiveRecord::Encryption::Key.new(key)
        arkey.public_tags.encrypted_data_key_id = dummy_key.id
        arkey.public_tags.add({ anti_nonce_exhaustion_data: anti_nonce_exhaustion_data })
        GitHub.dogstats.increment("encrypted_column.github_key_provider.encryption_key", tags: ["table:#{@table}", "attribute:#{@attribute}"])
        arkey
      end

      def decryption_keys(encrypted_message)
        key_id = encrypted_message.headers.encrypted_data_key_id
        candidate_keys = @keys.map { |k| ActiveRecord::Encryption::Key.new(k) }

        keys = get_matching_keys(candidate_keys, key_id)
        validate_at_least_one_matching_key!(keys, candidate_keys, key_id)

        latest_key = if keys.length == 1
          keys.first.id == ActiveRecord::Encryption::Key.new(@keys.last).id
        else
          false
        end

        GitHub.dogstats.increment("encrypted_column.github_key_provider.decryption_keys", tags: ["collision:#{keys.length > 1}", "latest_key:#{latest_key}", "table:#{@table}", "attribute:#{@attribute}"])
        keys.map do |key|
          ActiveRecord::Encryption::Key.new(rematerialize_key(key, encrypted_message))
        end
      end

      private

      def stat_validation_error(reason)
        GitHub.dogstats.increment("encrypted_column.github_key_provider.error", tags: ["validation:#{reason}", "table:#{@table}", "attribute:#{@attribute}"])
      end

      def validate_salt!(salt)
        unless salt.is_a?(Symbol)
          stat_validation_error("salt")
          raise InvalidSaltError.new("Expected salt to be a symbol")
        end
      end

      def validate_keys_available!(keys)
        if keys.nil?
          stat_validation_error("keys_available")
          raise KeyNotFoundError.new("ENCRYPTED_COLUMN_KEYING_MATERIAL environment variable not populated")
        end
      end

      def validate_at_least_one_key!(keys)
        if keys.length < 1
          stat_validation_error("at_least_one_key")
          raise KeyNotFoundError.new("No keys could be found in ENCRYPTED_COLUMN_KEYING_MATERIAL environment variable")
        end
      end

      def validate_at_least_one_matching_key!(matching_keys, candidate_keys, key_id)
        if matching_keys.length < 1
          stat_validation_error("missing_key")
          raise KeyNotFoundError.new("No matching keys for key_id: #{key_id} in ENCRYPTED_COLUMN_KEYING_MATERIAL environment variable. Available key ids: #{candidate_keys.map(&:id).join(", ")} - when decrypting #{@table}::#{@attribute}")
        end
      end

      def validate_current_encryption_key_available!(current_encryption_key)
        if current_encryption_key.nil?
          stat_validation_error("current_encryption_key_available")
          raise KeyNotFoundError.new("ENCRYPTED_COLUMN_CURRENT_ENCRYPTION_KEY environment variable not populated")
        end
      end

      def validate_keys_contain_current_encryption_key!(keys, current_encryption_key)
        if keys.exclude? current_encryption_key
          stat_validation_error("keys_contain_current_encryption_key")
          raise KeyConsistencyError.new("ENCRYPTED_COLUMN_KEYING_MATERIAL environment variable does not contain ENCRYPTED_COLUMN_CURRENT_ENCRYPTION_KEY")
        end
      end

      def validate_key_length!(key)
        if key.bytesize != 32
          stat_validation_error("key_length")
          raise KeyLengthError.new("Key (stored in ENCRYPTED_COLUMN_KEYING_MATERIAL) must be 32 bytes")
        end
      end

      def validate_current_encryption_key_length!(key)
        if key.bytesize != 32
          stat_validation_error("current_encryption_key_length")
          raise KeyLengthError.new("Key (stored in ENCRYPTED_COLUMN_CURRENT_ENCRYPTION_KEY) must be 32 bytes")
        end
      end

      def build_key(encryption_key)
        anti_nonce_exhaustion_data = Date.today.year.to_s
        key = OpenSSL::KDF::hkdf(encryption_key, salt: @salt, info: anti_nonce_exhaustion_data, length: AES_SIZE / 8, hash: OpenSSL::Digest::SHA256.new)
        [key, @salt, anti_nonce_exhaustion_data]
      end

      def rematerialize_key(main_key, message)
        anti_nonce_exhaustion_data = message.headers[:anti_nonce_exhaustion_data]
        OpenSSL::KDF::hkdf(main_key.secret, salt: @salt, info: anti_nonce_exhaustion_data, length: AES_SIZE / 8, hash: OpenSSL::Digest::SHA256.new)
      end

      def get_matching_keys(candidate_keys, key_id)
        candidate_keys.find_all { |k| k.id == key_id }
      end
    end
  end
end
