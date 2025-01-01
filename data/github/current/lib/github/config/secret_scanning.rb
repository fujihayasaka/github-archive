# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module SecretScanning

      # TODO this should go in our package
      sig { params(token: String).returns(String) }
      def encrypt_and_encode_token_for_secret_scanning(token)
        primary_box = primary_dotcom_secret_scanning_simple_box

        encrypted = primary_box.encrypt(token)
        Base64.urlsafe_encode64(encrypted)
      end

      # This method is only used in tests to verify token encryption and decryption.
      # It is necessary to ensure correct round-trip behavior in test cases.

      sig { params(encoded: T.nilable(String)).returns(T.nilable(String)) }
      def decode_and_decrypt_token_for_secret_scanning(encoded)
        return if encoded.nil?

        boxes = dotcom_secret_scanning_simple_boxes
        Kernel.raise RuntimeError.new("dotcom_secret_scanning_simple_box_keys not set") if boxes.empty?

        decoded = Base64.urlsafe_decode64(encoded)
        last_error = T.let(nil, T.nilable(StandardError))

        # Try each box until one successfully decrypts
        boxes.each do |box|
          begin
            return box.decrypt(decoded)
          rescue StandardError => e
            last_error = e
            # Continue to next key if decryption fails
            next
          end
        end

        # If we get here, none of the keys could decrypt the token
        # Re-raise the last error we encountered
        Kernel.raise last_error if last_error
      end

      sig { params(keys: String).void }
      def dotcom_secret_scanning_simple_box_keys=(keys)
        @dotcom_secret_scanning_simple_box_keys = T.let(keys, T.nilable(String))
      end

      sig { returns(T::Array[String]) }
      def dotcom_secret_scanning_simple_box_keys
        keys = @dotcom_secret_scanning_simple_box_keys || ENV["DOTCOM_SECRET_SCANNING_BOX_KEYS"]

        return [] if keys.nil? || keys.empty?

        keys.split(",").filter_map do |key|
          stripped = key.strip
          stripped unless stripped.empty?
        end
      end

      private

      sig { returns(T::Array[RbNaCl::SimpleBox]) }
      def dotcom_secret_scanning_simple_boxes
        @dotcom_secret_scanning_simple_boxes ||= T.let(
          dotcom_secret_scanning_simple_box_keys.map do |key|
            # Keys are raw strings, convert to binary with .b
            RbNaCl::SimpleBox.from_secret_key(key.b)
          end,
          T.nilable(T::Array[RbNaCl::SimpleBox])
        )
      end

      sig { returns(RbNaCl::SimpleBox) }
      def primary_dotcom_secret_scanning_simple_box
        Kernel.raise RuntimeError.new("dotcom_secret_scanning_simple_box_keys not set") if dotcom_secret_scanning_simple_boxes.empty?
        T.must(dotcom_secret_scanning_simple_boxes.first)
      end

    end
  end

  extend Config::SecretScanning
end
