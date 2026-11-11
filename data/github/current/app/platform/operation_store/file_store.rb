# typed: true
# frozen_string_literal: true

require "json"

module Platform
  module OperationStore
    class FileStore
      CLIENT_NAME_WILDCARD = Platform::OperationStore::ApplicationRecordBackend::CLIENT_NAME_WILDCARD

      # returns the body of the operation or nil if the client or operation do not exist
      def self.fetch(client_name, operation_id)
        # Fetch the operation from the ui manifest
        operation = relay_queries[operation_id]
        client = operation&.dig(:owner)
        query = operation&.dig(:query)

        if client.nil? || query.nil?
          # Fall back to server persisted queries
          server_op = server_persisted_queries[operation_id]
          if server_op
            owner = server_op["owner"]
            return server_op["query"], owner if owner == client_name || client_name == CLIENT_NAME_WILDCARD
          end
          return nil
        end

        if client == client_name || client_name == CLIENT_NAME_WILDCARD
          return query, client
        end

        nil
      end

      def self.fetch_all(client_name)
        operations = {}

        # loop through all the queries in the relay manifest, and add any which match the client_name
        relay_queries.each do |operation_id, record|
          client = record[:owner]
          query = record[:query]

          if client == client_name || client_name == CLIENT_NAME_WILDCARD
            operations[operation_id] = query
          end
        end

        # Include server persisted queries
        server_persisted_queries.each do |operation_id, record|
          owner = record["owner"]
          if owner == client_name || client_name == CLIENT_NAME_WILDCARD
            operations[operation_id] = record["query"]
          end
        end

        operations
      end

      def self.fetch_clients
        clients = Set.new

        # loop through all the queries in the relay manifest, and add any which match the client_name
        relay_queries.each do |_, record|
          client = record[:owner]
          clients << client
        end

        server_persisted_queries.each do |_, record|
          clients << record["owner"] if record["owner"]
        end

        clients.to_a
      end

      def self.relay_queries
        GitHubUI::Manifest.new.relay_manifest[:queries]
      end

      def self.server_persisted_queries
        @server_persisted_queries ||= begin
          path = File.join(GitHub::AppEnvironment.root, "config", "persisted_queries", "query_manifest.json")
          File.exist?(path) ? JSON.parse(File.read(path)) : {}
        end
      end
    end
  end
end
