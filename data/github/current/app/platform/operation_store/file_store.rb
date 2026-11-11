# typed: true
# frozen_string_literal: true

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

        return nil if client.nil? || query.nil?

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

        operations
      end

      def self.fetch_clients
        clients = Set.new

        # loop through all the queries in the relay manifest, and add any which match the client_name
        relay_queries.each do |_, record|
          client = record[:owner]
          clients << client
        end

        clients.to_a
      end

      def self.relay_queries
        GitHubUI::Manifest.new.relay_manifest[:queries]
      end
    end
  end
end
