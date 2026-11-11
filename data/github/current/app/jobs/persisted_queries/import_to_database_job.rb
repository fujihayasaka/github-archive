# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module PersistedQueries
  class ImportToDatabaseJob < ApplicationJob
    @@enabled = true
    queue_as :persisted_queries_import_to_db

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    # Only one of these jobs should run at any given time.
    locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

    def perform
      clients, created_clients = find_or_create_clients!(names: Platform::OperationStore::FileStore.fetch_clients)

      GitHub.dogstats.gauge("graphql.operation_store.clients.created", created_clients)

      clients.each do |client|
        Platform::OperationStore::ApplicationRecordBackend::GraphqlOperation.transaction do
          created_operations = create_missing_operations!(client: client, operations: Platform::OperationStore::FileStore.fetch_all(client.name))
          GitHub.dogstats.gauge("graphql.operation_store.operations.created", created_operations, tags: ["client:#{client.name}"])
        end
      end
    end

    private

    def find_or_create_clients!(names:)
      existing_clients = Platform::OperationStore::ApplicationRecordBackend::GraphqlClient.where(name: names)
      existing_client_names = existing_clients.pluck(:name)
      missing_client_names = names - existing_client_names

      return [existing_clients, 0] if missing_client_names.empty?

      missing_clients = missing_client_names.map do |name|
        {
          name: name,
          created_at: Time.current,
          updated_at: Time.current,
        }
      end

      with_write do
        Platform::OperationStore::ApplicationRecordBackend::GraphqlClient.insert_all!(missing_clients)

        # insert_all doesn't return created records, so we need get the clients again
        clients = Platform::OperationStore::ApplicationRecordBackend::GraphqlClient.where(name: names)
        [clients, missing_clients.size]
      end
    end

    def create_missing_operations!(client:, operations:)
      operation_ids = operations.keys

      # Note: we join against graphql_client_operations to ensure accurate client associations
      existing_operations = Platform::OperationStore::ApplicationRecordBackend::GraphqlOperation
        .joins("LEFT JOIN graphql_client_operations ON graphql_client_operations.graphql_operation_id = graphql_operations.id")
        .where(digest: operation_ids)
        .pluck(:digest, :graphql_client_id)

      missing_operation_digests = operation_ids - existing_operations.map(&:first)
      missing_client_operation_digests = existing_operations.filter_map { |digest, client_id| digest if client_id.nil? }

      return 0 if missing_operation_digests.empty? && missing_client_operation_digests.empty?

      missing_operations_attrs = missing_operation_digests.map do |digest|
        body = operations[digest]
        operation_name = GraphQL.parse(body).definitions.first.name&.truncate(Platform::OperationStore::ApplicationRecordBackend::GraphqlOperation::NAME_LENGTH_LIMIT) || digest

        {
          digest: digest,
          body: body,
          name: operation_name,
          created_at: Time.current,
          updated_at: Time.current,
        }
      end

      with_write do
        Platform::OperationStore::ApplicationRecordBackend::GraphqlOperation.insert_all!(missing_operations_attrs) unless missing_operations_attrs.empty?

        missing_operations = Platform::OperationStore::ApplicationRecordBackend::GraphqlOperation.where(digest: missing_operation_digests + missing_client_operation_digests)
        create_client_operations!(client: client, operations: missing_operations)
      end

      missing_operation_digests.size + missing_client_operation_digests.size
    end

    def create_client_operations!(client:, operations:)
      client_operations = operations.map do |operation|
        {
          graphql_client_id: client.id,
          graphql_operation_id: operation.id,
          alias: operation.digest
        }
      end

      Platform::OperationStore::ApplicationRecordBackend::GraphqlClientOperation.insert_all!(client_operations)
    end
  end
end
