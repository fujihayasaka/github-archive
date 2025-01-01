# typed: true
# frozen_string_literal: true

require "azure/storage/common"

module GitHub
  # This class acts as a bridge between a GitHub::Azure token provider and an Azure Storage token credential.
  # it also works around a bug in the Azure SDK where it waits until _after_ the token is expired before getting a new one.
  #
  # This class is almost a drop-in replacement for ::Azure::Storage::Common::Core::TokenCredential,
  # but you need to pass in the token provider instead of a token.
  #
  # I was a bit surprised there was nothing in the official libraries to do this, so if I've just missed it and you find one feel free to replace this.
  class AzureTokenCredential < ::Azure::Storage::Common::Core::TokenCredential
    MINIMUM_TOKEN_TTL = 1.minute

    def initialize(token_provider)
      super(nil)
      @token_provider = token_provider
      token
    end

    def token
      @mutex.synchronize do
        if @token_expires.nil? || @token_expires < Time.now + MINIMUM_TOKEN_TTL
          # The Azure SDK is broken, and waits until _after_ the token is expired before getting a new one. We request a new one manually, bypassing the expiration checking.
          @token_provider.send(:acquire_token)
          @token = @token_provider.token
          @token_expires = @token_provider.token_expires_on
        end
        @token
      end
    end
  end
end
