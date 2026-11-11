module Zuorest
  # TokenStorage interface for OAuth tokens
  #
  # This interface defines the contract that all token storage backends must implement.
  # Implementations of this interface are used by RestClient to store and retrieve OAuth tokens.
  # Storage implementations should only be concerned with storing and retrieving the raw token data
  # as a hash, not with parsing or serializing the OAuth2::AccessToken object.
  class TokenStorage
    # Get the token data from storage
    #
    # @param key [String] The key to identify the token
    # @return [Hash, nil] The token data hash or nil if not found
    def get(key)
      raise NotImplementedError, "#{self.class} does not implement #get"
    end

    # Store token data
    #
    # @param key [String] The key to identify the token
    # @param data [Hash] The token data to store
    # @return [void]
    def store(key, data)
      raise NotImplementedError, "#{self.class} does not implement #store"
    end

    # Generate a storage key for a client
    #
    # @param client_id [String] The OAuth client ID
    # @param server_url [String] The server URL
    # @return [String] A unique key for this client configuration
    def self.generate_key(client_id, server_url)
      "zuorest:oauth_token:#{client_id}:#{server_url.gsub(/[^\w]/, '_')}"
    end
  end
end