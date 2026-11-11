# typed: true
# frozen_string_literal: true

require_relative "encryption_errors"

module GitHub
  module Encryption
    class NoOpKeyProvider
      def encryption_key
        raise NotImplementedError.new("This method should not be called")
      end

      def decryption_keys(encrypted_message)
        raise NotImplementedError.new("This method should not be called")
      end
    end
  end
end
