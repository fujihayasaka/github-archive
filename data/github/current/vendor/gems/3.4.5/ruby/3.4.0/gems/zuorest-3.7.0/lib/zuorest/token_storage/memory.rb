require "zuorest/token_storage"

module Zuorest
  class TokenStorage
    # In-memory implementation of TokenStorage
    #
    # This implementation stores token data as hashes in memory.
    # Tokens are not shared between different processes.
    class Memory < TokenStorage
      def initialize
        @tokens = {}
      end

      # Get the token data from memory
      #
      # @param key [String] The key to identify the token
      # @return [Hash, nil] The token data hash or nil if not found
      def get(key)
        @tokens[key]
      end

      # Store token data in memory
      #
      # @param key [String] The key to identify the token
      # @param data [Hash] The token data to store
      # @return [void]
      def store(key, data)
        @tokens[key] = data
      end
    end
  end
end
