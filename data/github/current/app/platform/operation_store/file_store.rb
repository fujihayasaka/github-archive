# typed: true
# frozen_string_literal: true

module Platform
  module OperationStore
    class FileStore
      OPERATIONS_FILE_PATH = Rails.root.join("config/persisted_graphql_queries_by_serviceowner/")
      CLIENT_NAME_WILDCARD = Platform::OperationStore::ApplicationRecordBackend::CLIENT_NAME_WILDCARD

      # returns the body of the operation or nil if the client or operation do not exist
      def self.fetch(client_name, operation_id)
        # Note: we use fetch_clients so we don't put the untrusted `client_name` into a filesystem call
        fetch_clients.each do |safe_client|
          next unless safe_client == client_name || client_name == CLIENT_NAME_WILDCARD

          filename = OPERATIONS_FILE_PATH.join("#{safe_client}.json")
          operations = JSON.parse(File.read(filename))

          if operations[operation_id]
            return operations[operation_id], safe_client
          end
        end

        nil
      end

      def self.fetch_all(client_name)
        # Note: we use fetch_clients so we don't put the untrusted `client_name` into a filesystem call
        safe_client = client_name if fetch_clients.include?(client_name)

        return nil unless safe_client

        filename = OPERATIONS_FILE_PATH.join("#{safe_client}.json")
        JSON.parse(File.read(filename))
      end

      def self.fetch_clients
        Dir.glob(OPERATIONS_FILE_PATH.join("*.json")).map do |filename|
          File.basename(filename, ".json")
        end
      end
    end
  end
end
