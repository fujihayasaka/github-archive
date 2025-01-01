# typed: true
# frozen_string_literal: true

require "graphql/pro/operation_store"

module Platform
  module OperationStore
    # This originally comes from the graphql-pro gem, but because of linter
    # rules around ActiveRecord base classes we can't easily inherit from the
    # original class definition, so this is all copied over for our use
    class ApplicationRecordBackend
      include GitHub::ResilienceMixin

      CLIENT_NAME_WILDCARD = "*"

      def initialize(operation_store:)
        @operation_store = operation_store
      end

      def supports_batch_upsert?
        ActiveRecord::Base.respond_to?(:insert_all)
      end

      # @return [Array<AddResult>]
      def batch_upsert_client_operations(client, operation_hashes, changeset_version: nil, context: nil)
        results = []
        ops_by_digest = {}
        operation_hashes.map { |h| ops_by_digest[h[:operation_digest]] = h }
        already_present_operations = GraphqlOperation
          .where(digest: ops_by_digest.keys)
          .pluck("graphql_operations.digest, graphql_operations.id")

        already_present_operations.each do |(digest, operation_id)|
          incoming_defn = ops_by_digest[digest]
          incoming_defn[:graphql_operation_id] = operation_id
        end

        operation_completely_missing = ops_by_digest.values.select { |defn| defn[:graphql_operation_id].nil? }

        if operation_completely_missing.any?
          index_entry_names = Set.new
          index_reference_attrs = []

          operation_attributes = operation_completely_missing.map do |defn|
            errs, query = GraphQL::Pro::OperationStore::Validate.validate(@operation_store.schema, defn[:operation_document], client_name: client.name, changeset_version: changeset_version)
            if errs.any?
              GraphQL::Pro::OperationStore.debug { errs.map(&:to_h) }
              error_messages = errs.map do |e|
                locations = e.to_h["locations"]
                  .select { |l| l["line"] }
                  .map { |l| "#{l["line"]}:#{l["column"]}" }
                  .join(", ")

                if !locations.empty?
                  locations = " (#{locations})"
                end

                "#{e.message}#{locations}"
              end
              result = GraphQL::Pro::OperationStore::AddResult.new(:failed, errors: error_messages, operation_alias: defn[:operation_alias])
              results << result
              return results
            end
            defn[:query] = query
            index_entry_names.merge(query.context[:index_entries])
            {
              digest: defn[:operation_digest],
              body: defn[:definition_string],
              name: defn[:operation_name],
              created_at: Time.now, # Some Rails versions don't automatically set this.
              updated_at: Time.now, # Some Rails versions don't automatically set this.
            }
          end
          GraphqlOperation.insert_all!(operation_attributes)
          # First, create a map of { key => entry_object } to use below
          entries = {}
          GraphqlIndexEntry.where(name: index_entry_names).each do |entry|
            entries[entry.name] = entry
          end

          new_keys = index_entry_names - entries.keys
          if new_keys.any?
            GraphqlIndexEntry.insert_all!(
              new_keys.map { |k| { name: k } }
            )
            new_entries = GraphqlIndexEntry.where(name: new_keys)
            new_entries.each do |new_entry|
              entries[new_entry.name] = new_entry
            end
          end

          # Annoyingly, databases don't return newly-created records, so you have to refetch them to get their new primary keys
          new_operations = GraphqlOperation.where(digest: operation_attributes.map { |h| h[:digest] })
          new_operations.each do |op|
            op_hash = ops_by_digest[op.digest]
            op_hash[:graphql_operation_id] = op.id
            index_entries = op_hash[:query].context[:index_entries]
            new_reference_attrs = index_entries.map do |ie|
              entry = entries[ie] || raise(Platform::Errors::InternalExecution.new("Missing entry for #{ie.inspect}"))
              {
                graphql_index_entry_id: entry.id,
                graphql_operation_id: op.id
              }
            end

            index_reference_attrs.concat(new_reference_attrs)
          end

          if index_reference_attrs.any?
            GraphqlIndexReference.insert_all!(index_reference_attrs)
          end
        end

        already_present_client_operation_aliases = GraphqlClientOperation
          .where(
            graphql_client_id: client.id,
            graphql_operation_id: ops_by_digest.values.map { |v| v[:graphql_operation_id] }
          )
          .pluck("alias")

        already_present_client_operation_aliases.each do |op_alias|
          op_hash = operation_hashes.find { |op| op[:operation_alias] == op_alias }
          # it's possible this won't be found, if the operation
          # was previously uploaded with a different alias.
          if op_hash
            ops_by_digest.delete(op_hash[:operation_digest])
            results << GraphQL::Pro::OperationStore::AddResult.new(:not_modified, operation_alias: op_alias)
          end
        end

        if ops_by_digest.any?
          client_operation_attributes = ops_by_digest.map do |_digest, defn|
            {
              graphql_client_id: client.id,
              graphql_operation_id: defn[:graphql_operation_id],
              alias: defn[:operation_alias],
              created_at: Time.now, # Some Rails versions don't automatically set this.
              updated_at: Time.now, # Some Rails versions don't automatically set this.
            }
          end
          GraphqlClientOperation.insert_all!(client_operation_attributes)
          client_operation_attributes.each do |client_op_attr|
            results << GraphQL::Pro::OperationStore::AddResult.new(:added, operation_alias: client_op_attr[:alias], operation_record: client_op_attr)
          end
        end

        results
      rescue ActiveRecord::RecordNotUnique => err
        GraphQL::Pro::OperationStore.debug(err: err)
        err_message = "Uniqueness validation failed: make sure operation aliases are unique for '#{client.name}'"
        T.must(results) << GraphQL::Pro::OperationStore::AddResult.new(:failed, errors: [err_message], operation_alias: nil)
        results
      end

      # Attach this operation to an already-existing client named `client_name`,
      # no-op if it's already attached.
      # @param client [ClientRecord]
      # @param body [String] The GraphQL operation body
      # @param digest [String] digest of the body
      # @param op_name [String]
      # @param operation_alias [String] The client-provided ID
      # @return [AddResult]
      def upsert_client_operation(client, body, digest, op_name, operation_alias)
        operation = GraphqlOperation.where(digest: digest).first
        # If it didn't already exist, create and index it
        if operation.nil?
          operation = GraphqlOperation.create!(digest: digest, body: body, name: op_name)
        end

        client_operation_attrs = {
          graphql_client_id: client.id,
          graphql_operation_id: operation.id,
          alias: operation_alias,
        }

        # first_or_intialize_by isn't supported on Rails 3
        client_operation_record = GraphqlClientOperation.where(client_operation_attrs).first
        if client_operation_record.nil?
          GraphqlClientOperation.create!(client_operation_attrs)
          GraphQL::Pro::OperationStore::AddResult.new(:added, operation_alias: operation_alias, operation_record: operation)
        else
          GraphQL::Pro::OperationStore::AddResult.new(:not_modified, operation_alias: operation_alias)
        end
      rescue ActiveRecord::RecordNotUnique => err
        GraphQL::Pro::OperationStore.debug(err: err)
        err_message = "Uniqueness validation failed: make sure operation aliases are unique for '#{client.name}'"
        GraphQL::Pro::OperationStore::AddResult.new(:failed, errors: [err_message], operation_alias: operation_alias)
      end

      # Return the persisted operation named `operation_digest` for the client named `client_name`
      # @param client_name (pass "*" wildcard to search all clients)  [String]
      # @param operation_digest [String]
      # @return [OperationRecord, catalog_service, graphql_document]
      def get_operation(client_name, operation_digest, touch_last_used_at:)
        db_operation_record = nil
        operation_attrs = nil
        tags = [client_tag(client_name)]
        timer = Timer.start
        is_missing_from_db = false

        # check the LRU cache first before checking the database
        query_with_client = fetch_operation_from_cache(client_name, operation_digest)
        if query_with_client
          tags << "store:cache"
          graphql_document, owning_client = query_with_client

          operation_attrs = {
            graphql_document: graphql_document,
            digest: operation_digest,
            client: owning_client,
          }
        else
          # check db for operation if not in local cache
          db_operation_record = T.let(nil, T.untyped)
          viewer = GitHub.context[:actor] && User.find_by_login(GitHub.context[:actor])

          with_database_error_fallback do
            db_operation_record = fetch_operation_from_db(client_name, operation_digest)
          end

          if db_operation_record
            tags << "store:db"
            query = db_operation_record.operation_body
            owning_client = db_operation_record.client
          # not in cache or db, so check files
          else
            is_missing_from_db = true
            tags << "store:file"
            query, owning_client = fetch_operation_from_file_store(client_name, operation_digest)

            # we can bounce early if we didn't find the operation in the file store (the last frontier)
            if !query
              GitHub.logger.warn(
                "Persisted query could not be found.",
                "graphql.operation.digest": operation_digest,
                "graphql.client.name": client_name,
                "code.namespace": "Platform::OperationStore::ApplicationRecordBackend",
                "code.function": __method__,
              )

              return
            end

            # Querying the FileStore is slow, so we schedule a job that will sync all missing operations to the DB.
            PersistedQueries::ImportToDatabaseJob.perform_later
          end

          # update the cache with record from DB or file store
          graphql_document = GraphQL.parse(query)
          Cache.write(operation_digest, graphql_document, owning_client)

          # We want to ensure this query is persisted in the DB, so we write it now.
          # Note: we do this in addition to scheduling a job (above) because its possible the job
          # will be picked up by a older worker that doesn't have the new query in its file store.
          if is_missing_from_db
            operation_name = get_operation_name(graphql_document, operation_digest)
            ActiveRecord::Base.connected_to(role: :writing) do
              client_record = upsert_client(owning_client, "")
              upsert_client_operation(client_record, query, operation_digest, operation_name, operation_digest)
            end
          end

          operation_attrs = {
            id: db_operation_record&.operation_id,
            graphql_document: graphql_document,
            digest: operation_digest,
            client: owning_client,
          }
        end

        timer.stop
        tags << "operation_name:#{get_operation_name(operation_attrs[:graphql_document], operation_digest)}"
        GitHub.dogstats.distribution("graphql.operation_store.fetch", timer.elapsed_ms(4), tags: tags)

        # shouldn't hit this case. It would mean we failed to cache in-memory and to persist to the db
        if operation_attrs.blank?
          GitHub.logger.warn(
            "Persisted query could not be found.",
            "graphql.operation.digest": operation_digest,
            "code.namespace": "Platform::OperationStore::ApplicationRecordBackend",
            "code.function": __method__,
          )

          return
        end

        # Only run this update if this instance of the operation store has been migrated
        if operation_attrs[:id] && supports_last_used_at? && touch_last_used_at
          last_used_at = Time.now.utc
          @operation_store.touch_last_used_at(operation_attrs[:id], last_used_at)
        end

        [operation_attrs[:client], graphql_document]
      end

      def update_last_used_ats(last_used_ats)
        # TODO: conceivably, we could use Rails 6 upsert_all here. But the problem is,
        # it requires _all_ attributes of the model to be present here, which isn't
        # easy because of how it's fetched above. If we run into issues with
        # too much db traffic here, we can pursue that option further.
        ActiveRecord::Base.connected_to(role: :writing) do
          last_used_ats.each do |(client_operation_record_id, new_last_used_at)|
            GraphqlClientOperation
              .where(id: client_operation_record_id)
              .update_all(last_used_at: new_last_used_at)
          end
        end
      end

      # Return the operation matching `digest`, used for the dashboard.
      # @param digest [String]
      # @return [OperationRecord, nil]
      def get_operation_by_digest(digest)
        ar_op = GraphqlOperation
            .joins("
              LEFT JOIN (
                SELECT
                  #{supports_last_used_at? ? "max(last_used_at)" : "NULL"} as last_used_at,
                  #{supports_is_archived? ? "SUM(CASE WHEN is_archived THEN 0 ELSE 1 END)" : "COUNT(*)"} as active_count,
                  graphql_operation_id
                FROM graphql_client_operations
                GROUP BY graphql_operation_id
              ) AS ops_count ON ops_count.graphql_operation_id = graphql_operations.id
            ")
            .select(%w[body digest name active_count last_used_at])
            .where(digest: digest)
            .first

        if ar_op
          GraphQL::Pro::OperationStore::OperationRecord.new(
            body: ar_op.body,
            digest: ar_op.digest,
            name: ar_op.name,
            clients_count: nil,
            is_archived: T.unsafe(ar_op).active_count == 0,
            last_used_at: T.unsafe(ar_op).last_used_at,
          )
        else
          nil
        end
      end

      # Delete this operation, if it exists.
      # WARNING: this is only for use from the dashboard;
      # It will break clients if you delete operations that they're using.
      #
      # @param operation_id [String]
      # @return void
      def delete_operation(operation_id)
        operation = GraphqlOperation.where(digest: operation_id).first
        if operation
          operation.destroy
        end
      end

      # Create or fetch the client identified by `name`,
      # and set its secret to `secret`.
      # @param name [String] the client to find or create
      # @param secret [String] not used in this implementation
      # @return [ClientRecord]
      def upsert_client(name, secret)
        ar_client = get_ar_client_by_name(name) || GraphqlClient.new(name: name)

        ar_client.save!
        Platform::OperationStore::ClientRecord.new(
          id: ar_client.id,
          name: ar_client.name,
          created_at: ar_client.created_at,
          last_synced_at: nil,
          operations_count: 0,
          archived_operations_count: 0,
          last_used_at: nil,
        )
      end

      # Fetch the client named `name`, if it exists
      # @param name [String]
      # @return [Client, nil]
      def get_client(name)
        ar_client = get_ar_client_by_name(name)
        if ar_client
          Platform::OperationStore::ClientRecord.new(
            id: ar_client.id,
            name: ar_client.name,
            created_at: ar_client.created_at,
            last_synced_at: nil,
            operations_count: 0,
            archived_operations_count: 0,
            last_used_at: nil,
          )
        end
      end

      # Delete the client named `name`, if it exists
      # @param name [String]
      # @return [void]
      def delete_client(name)
        client = GraphqlClient.where(name: name).take # Avoid adding ordering with `.first`
        if client
          client.destroy
        end
      end

      # Accept a block and yield a callable which,
      # when `.call`ed, rolls back any persistence operations which
      # were fulfilled already.
      #
      # If the backend doesn't support transactions, `rollback` can be
      # implemented as a no-op and partial saves will be used instead.
      def transaction
        GraphqlClient.transaction do
          rollback = -> { raise ActiveRecord::Rollback } # rubocop:disable GitHub/UsePlatformErrors
          yield(rollback)
        end
      end

      # Remove all index entries; used for preparing a re-index.
      # @return [void]
      def purge_index
        GraphqlIndexEntry.delete_all
        GraphqlIndexReference.delete_all
      end

      # Get the existing entry for `key`, or return a new, empty one.
      # @param key [String]
      # @return [IndexEntryRecord]
      def get_index_entry(key)
        ar_entry = index_entries_with_joins.where(name: key).first

        GraphQL::Pro::OperationStore::IndexEntryRecord.new(
          name: key,
          persisted: !!ar_entry,
          references_count: ar_entry ? ar_entry.references_count : 0,
          archived_references_count: ar_entry ? ar_entry.archived_references_count : 0,
          last_used_at: ar_entry ? ar_entry.last_used_at : nil,
        )
      end

      # Read from the index to find all operations which reference `key`
      # @param key [String] An index entry key, like `Mutation.updateUser`
      # @return [Array<OperationRecord>]
      def get_operations_by_index_entry(key)
        ar_entry = GraphqlIndexEntry.where(name: key).first
        if ar_entry
          ops = ar_entry
            .graphql_index_references
            .joins("
              LEFT JOIN graphql_operations ON graphql_index_references.graphql_operation_id = graphql_operations.id
              LEFT JOIN (
                SELECT
                  graphql_operation_id,
                  #{supports_is_archived? ? "SUM(CASE WHEN is_archived THEN 0 ELSE 1 END)" : "1"} as active_count
                FROM
                  graphql_client_operations
                GROUP BY
                  graphql_operation_id
              ) as client_ops ON client_ops.graphql_operation_id = graphql_operations.id
            ")
            .select([
              "graphql_operations.name as operation_name",
              "graphql_operations.digest as operation_digest",
              "graphql_operations.body as operation_body",
              "client_ops.active_count as active_count"
            ])
          ops.map do |ref|
            GraphQL::Pro::OperationStore::OperationRecord.new(
              name: T.unsafe(ref).operation_name,
              digest: T.unsafe(ref).operation_digest,
              body: T.unsafe(ref).operation_body,
              clients_count: nil,
              is_archived: T.unsafe(ref).active_count == 0,
              last_used_at: nil,
            )
          end
        else
          []
        end
      end

      # Find all client-operation reference records for the operation matching `digest`.
      # @param digest [String]
      # @return [Array<GraphQLClientOperation>]
      def get_client_operations_by_digest(digest)
        ar_op = GraphqlOperation.where(digest: digest).first
        if ar_op
          ar_op.graphql_client_operations.includes(:graphql_client).map do |client_op|
            GraphQL::Pro::OperationStore::ClientOperationRecord.new(
              client_name: T.must(client_op.graphql_client).name,
              operation_alias: client_op.alias,
              digest: ar_op.digest,
              name: ar_op.name,
              created_at: client_op.created_at,
              is_archived: supports_is_archived? ? client_op.is_archived : false,
              last_used_at: client_op.respond_to?(:last_used_at) ? client_op.last_used_at : nil,
            )
          end
        else
          []
        end
      end

      # For the operation matching `digest`, return index entries derived from it.
      # @param digest [String]
      # @return [Array<IndexEntryRecord>]
      def get_index_entries_by_digest(digest)
        ar_op = GraphqlOperation.where(digest: digest).first
        if ar_op
          entries = ar_op.graphql_index_entries.all
          entries.each do |idx_entry|
            GraphQL::Pro::OperationStore::IndexEntryRecord.new(
              name: idx_entry.name,
              persisted: true,
              references_count: nil,
              archived_references_count: nil,
              last_used_at: nil
            )
          end
        else
          []
        end
      end

      # Update the index to reflect that these operations contain the referenced keys
      # @param operation_index_map [Hash<OperationRecord => Set<String>>] A map of operation => index keys to add to the database
      # @return [void]
      def create_index_references(operation_index_map)
        all_keys = []
        operation_index_map.each_value { |keys| all_keys.concat(keys.to_a) }
        all_keys.uniq!

        # First, create a map of { key => entry_object } to use below
        entries = {}
        GraphqlIndexEntry.where(name: all_keys).each do |entry|
          entries[entry.name] = entry
        end

        new_keys = all_keys - entries.keys
        if supports_batch_upsert? && new_keys.any?
          GraphqlIndexEntry.insert_all!(
            new_keys.map { |k| { name: k } }
          )
          new_entries = GraphqlIndexEntry.where(name: new_keys)
          new_entries.each do |new_entry|
            entries[new_entry.name] = new_entry
          end
        else
          new_keys.each do |key|
            entries[key] = GraphqlIndexEntry.create!(name: key)
          end
        end

        operation_index_map.each do |operation, keys|
          keys.each do |key|
            entry = entries[key] || raise(Platform::Errors::InternalExecution.new("Invariant: didn't find #{key.inspect} in entries cache (#{entries.keys})"))
            index_ref_attrs = {
              graphql_index_entry_id: entry.id,
              graphql_operation_id: operation.id,
            }
            if !GraphqlIndexReference.exists?(index_ref_attrs)
              GraphqlIndexReference.create!(index_ref_attrs)
            end
          end
        end
      end

      # Return client-operation references for the client named `client_name`, paginated.
      # @param client_name [String]
      # @param page [Integer]
      # @param per_page [Integer]
      # @return [DashboardPage<ClientOperationRecord>]
      def get_client_operations_by_client(client_name, page:, per_page:, order_by: nil, order_dir: nil, is_archived: false)
        order_by ||= "name"
        order_dir ||= :asc

        if order_by == "name"
          order_by = "graphql_operations.name"
        elsif order_by == "last_used_at"
          order_by = "graphql_client_operations.last_used_at"
        else
          raise Platform::Errors::ArgumentError, "Unexpected order_by: #{order_by.inspect}"
        end

        if order_dir != :asc && order_dir != :desc
          raise Platform::Errors::ArgumentError, "Unexpected order_dir: #{order_dir.inspect}"
        end

        client = get_ar_client_by_name(client_name)
        operations = client
          .graphql_client_operations
          .includes(:graphql_operation)

        if supports_is_archived?
          operations = operations.where(is_archived: is_archived)
        end

        operations = operations.order("#{order_by} #{order_dir}, graphql_client_operations.created_at")

        if operations.respond_to?(:references)
          # Sometimes rails thinks that the `includes` above is superfluous;
          # When we have the option, tell Rails that we really _do_ want it.
          operations = operations.references(:graphql_operation)
        end

        paginate_relation(operations, page: page, per_page: per_page) do |graphql_client_operation|
          GraphQL::Pro::OperationStore::ClientOperationRecord.new(
            client_name: client_name,
            operation_alias: graphql_client_operation.alias,
            digest: graphql_client_operation.graphql_operation.digest,
            name: graphql_client_operation.graphql_operation.name,
            created_at: graphql_client_operation.created_at,
            is_archived: supports_is_archived? ? graphql_client_operation.is_archived : false,
            last_used_at: graphql_client_operation.respond_to?(:last_used_at) ? graphql_client_operation.last_used_at : nil,
          )
        end
      end

      # Return a page of _all operations_ in the backend.
      # @param page [Integer]
      # @param per_page [Integer]
      # @return [DashboardPage<OperationRecord>]
      def all_operations(page:, per_page:, is_archived: false, order_by: nil, order_dir: nil)
        order_by ||= "name"
        order_dir ||= :asc
        if order_by != "name" && order_by != "last_used_at"
          raise Platform::Errors::ArgumentError, "Unexpected order_by: #{order_by.inspect}"
        elsif order_dir != :asc && order_dir != :desc
          raise Platform::Errors::ArgumentError, "Unexpected order_dir: #{order_dir.inspect}"
        end

        client_ops = GraphqlClientOperation
          .select([
            "count(*) as clients_count",
            "#{supports_last_used_at? ? "max(last_used_at)" : "NULL"} as last_used_at",
            "graphql_operation_id"
          ])

        if supports_is_archived?
          client_ops = client_ops.where(is_archived: is_archived)
        end

        client_ops = client_ops.group("graphql_operation_id")

        operations = GraphqlOperation
          .joins("
            LEFT JOIN (#{client_ops.to_sql})
              AS ops_count
              ON ops_count.graphql_operation_id = graphql_operations.id
          ")
          .select(%w[id name digest body clients_count last_used_at])
          .where("clients_count IS NOT NULL")
          .order("#{order_by} #{order_dir}") # Use a string so the PG driver doesn't get too smart with it


        paginate_relation(operations, page: page, per_page: per_page)
      end

      # Return a page of all index entries matching `search_term`.
      # @param search_term [String] A user-provided search query
      # @param page [Integer]
      # @param per_page [Integer]
      # @return [DashboardPage<IndexEntryRecord>]
      def all_index_entries(search_term:, page:, per_page:)
        entries = index_entries_with_joins.order("name ASC")

        if search_term
          entries = entries.where("name LIKE ?", "%#{search_term}%")
        end

        paginate_relation(entries, page: page, per_page: per_page)
      end

      # Return a page of all clients in the backend.
      # @param page [Integer]
      # @param per_page [Integer]
      # @return [DashboardPage<ClientRecord>]
      def all_clients(page:, per_page:, order_by: nil, order_dir: nil)
        # Override a passed-in nil
        order_by ||= "name"
        order_dir ||= :asc

        if order_by != "name" && order_by != "last_used_at"
          raise Platform::Errors::ArgumentError, "Unexpected order_by: #{order_by.inspect}"
        elsif order_dir != :asc && order_dir != :desc && !order_dir.nil?
          raise Platform::Errors::ArgumentError, "Unexpected order_dir: #{order_dir.inspect}"
        end

        clients = GraphqlClient
          .joins("
            LEFT JOIN (
              SELECT
                #{
                  if supports_is_archived?
                    "SUM(CASE WHEN is_archived THEN 0 ELSE 1 END) AS graphql_operations_count,
                      SUM(CASE WHEN is_archived THEN 1 ELSE 0 END) AS graphql_archived_operations_count,"
                  else
                    "COUNT(*) as graphql_operations_count, 0 as graphql_archived_operations_count,"
                  end
                  }
                MAX(created_at) AS last_synced_at,
                #{supports_last_used_at? ? "MAX(last_used_at)" : "NULL"} as last_used_at,
                graphql_client_id
              FROM graphql_client_operations
              GROUP BY graphql_client_id
            ) AS ops_count ON ops_count.graphql_client_id = graphql_clients.id
          ")
          .select([
            "name",
            "created_at",
            "COALESCE(graphql_operations_count, 0) AS operations_count",
            "COALESCE(graphql_archived_operations_count, 0) AS archived_operations_count",
            "last_synced_at",
            "last_used_at",
            "secret",
          ])
          .order("#{order_by} #{order_dir}") # Use a string so the PG driver doesn't get too smart with it

        paginate_relation(clients, page: page, per_page: per_page)
      end

      def archive_operations(digests:, is_archived:)
        GraphqlClientOperation
          .joins(:graphql_operation)
          .where("graphql_operations.digest" => digests)
          .update_all(is_archived: is_archived)
        nil
      end

      def archive_client_operations(client_name:, operation_aliases:, is_archived:)
        GraphqlClientOperation
          .joins(:graphql_client)
          .where("graphql_clients.name" => client_name, "alias" => operation_aliases)
          .update_all(is_archived: is_archived)
        nil
      end

      private

      def fetch_operation_from_cache(client_name, operation_id)
        cache_timer = Timer.start
        query_with_client = Cache.fetch(operation_id)
        cache_timer.stop
        GitHub.dogstats.distribution("graphql.operation_store.cache.fetch", cache_timer.elapsed_ms(4), tags: [client_tag(client_name), "hit:#{query_with_client ? "true" : "false"}"])
        query_with_client
      end

      def fetch_operation_from_file_store(client_name, operation_id)
        file_timer = Timer.start
        query_with_client = FileStore.fetch(client_name, operation_id)
        file_timer.stop
        GitHub.dogstats.distribution("graphql.operation_store.file_store.fetch", file_timer.elapsed_ms(4), tags: [client_tag(client_name), "hit:#{query_with_client ? "true" : "false"}"])
        query_with_client
      end

      def fetch_operation_from_db(client_name, operation_digest)
        is_client_wild = client_name == CLIENT_NAME_WILDCARD
        joins = ["LEFT JOIN graphql_operations ON graphql_operations.id = graphql_client_operations.graphql_operation_id"]
        joins << "LEFT JOIN graphql_clients ON graphql_clients.id = graphql_client_operations.graphql_client_id"
        where_conditions = { "graphql_client_operations.alias" => operation_digest }
        where_conditions["graphql_clients.name"] = client_name unless is_client_wild
        if supports_is_archived?
          where_conditions["graphql_client_operations.is_archived"] = false
        end
        db_timer = Timer.start
        client_operation_record = GraphqlClientOperation
          .select("
            graphql_client_operations.id as id,
            #{supports_last_used_at? ? "graphql_client_operations.last_used_at" : "NULL"} as last_used_at,
            graphql_operations.id as operation_id,
            graphql_operations.body as operation_body,
            graphql_operations.digest as operation_digest,
            graphql_clients.name as client
          ")
          .joins(joins)
          .where(where_conditions)
          .first
        db_timer.stop
        GitHub.dogstats.distribution("graphql.db_store.cache.fetch", db_timer.elapsed_ms(4), tags: [client_tag(client_name), "hit:#{client_operation_record ? "true" : "false"}"])

        client_operation_record
      end

      def client_tag(client_name)
        client_name == CLIENT_NAME_WILDCARD ? "" : "client_name:#{client_name}"
      end

      def supports_last_used_at?
        GraphqlClientOperation.column_names.include?("last_used_at")
      end

      def supports_is_archived?
        GraphqlClientOperation.column_names.include?("is_archived")
      end

      def paginate_relation(relation, page:, per_page:)
        offset = (page - 1) * per_page

        page_relation = relation.offset(offset).limit(per_page)
        # Reorder to avoid postgres bug?
        total = relation.reorder(nil).count(:all)
        page_total = page_relation.reorder(nil).count(:all)

        if page_total < total
          prev_page = offset > 0 ? page - 1 : false
          next_page = (offset + page_total) < total ? page + 1 : false
        else
          next_page = false
          prev_page = false
        end

        items = if block_given?
          page_relation.map { |i| yield(i) }
        else
          page_relation
        end

        GraphQL::Pro::OperationStore::DashboardPage.new(
          items: items,
          next_page: next_page,
          prev_page: prev_page,
          total_count: total,
        )
      end

      def get_ar_client_by_name(name)
        GraphqlClient.where(name: name).first
      end

      # @return [ActiveRecord::Relation] Index entries, with joins to count references and last_used_at
      def index_entries_with_joins
        GraphqlIndexEntry
          .joins("
            LEFT JOIN (
              SELECT
                SUM(unarchived_references_count) as references_count,
                SUM(archived_references_count) as archived_references_count,
                max(last_used_at) as last_used_at,
                graphql_index_entry_id
              FROM graphql_index_references
              LEFT JOIN (
                SELECT
                  id AS operation_id,
                  CASE WHEN unarchived_references_count > 0 THEN 1 ELSE 0 END as unarchived_references_count,
                  CASE WHEN unarchived_references_count = 0 THEN 1 ELSE 0 END as archived_references_count,
                  last_used_at
                FROM graphql_operations
                LEFT JOIN (
                  SELECT
                    #{supports_last_used_at? ? "max(last_used_at)" : "NULL"} as last_used_at,
                    #{supports_is_archived? ? "SUM(CASE WHEN is_archived THEN 0 ELSE 1 END)" : "COUNT(*)"} as unarchived_references_count,
                    graphql_operation_id
                  FROM graphql_client_operations
                  GROUP BY graphql_operation_id
                ) AS cl_ops ON cl_ops.graphql_operation_id = graphql_operations.id
              ) AS ops ON ops.operation_id = graphql_index_references.graphql_operation_id
              GROUP BY graphql_index_entry_id
            ) AS index_references ON index_references.graphql_index_entry_id = graphql_index_entries.id
          ")
          .select("
              name,
              last_used_at,
              references_count,
              archived_references_count
          ")
      end

      def get_operation_name(graphql_document, operation_digest)
        # defaulting to the operation digest if no operation name is provided
        operation_name = graphql_document.definitions.first.name&.truncate(GraphqlOperation::NAME_LENGTH_LIMIT) || operation_digest
      end
    end
  end
end
