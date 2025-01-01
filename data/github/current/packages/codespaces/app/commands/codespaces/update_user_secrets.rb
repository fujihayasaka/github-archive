# typed: true
# frozen_string_literal: true

module Codespaces

  class UpdateUserSecrets < Command
    class Error < Codespaces::Error; end
    class ConnectionFailed < Codespaces::UpdateUserSecrets::Error; end
    class BadResponse < Codespaces::UpdateUserSecrets::Error; end

    attr_reader :codespace, :github_token, :codespace_token

    def initialize(codespace:)
      @codespace = codespace
    end

    def perform
      begin
        client.update_user_secrets(codespace, secrets: secrets)
      rescue Codespaces::VscsClient::TimeoutError, Codespaces::VscsClient::ConnectionFailed
        raise ConnectionFailed, "Connection failed"
      rescue Codespaces::VscsClient::BadResponseError => e
        raise BadResponse, "Bad response"
      end
    end

    private

    def client
      @client ||= Codespaces::VscsClient.for_codespace(codespace)
    end

    def secrets
      Codespaces::Secret.assemble(codespace)
    end
  end
end
