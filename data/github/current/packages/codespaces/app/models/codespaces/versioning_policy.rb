# typed: true
# frozen_string_literal: true

module Codespaces
  module VersioningPolicy
    SUPPORTED_CLIENTS = { "vscode_extension" => { min_warn: "1.17.2", min_break: "1.17.2" } }

    # Returns the supported versions for a client
    def self.codespaces_clients_supported(client)
      return SUPPORTED_CLIENTS if client.nil?
      SUPPORTED_CLIENTS[client]
    end
  end
end
