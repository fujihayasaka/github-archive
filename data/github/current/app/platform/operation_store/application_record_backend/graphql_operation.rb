# typed: true
# frozen_string_literal: true

module Platform
  module OperationStore
    class ApplicationRecordBackend
      # A GraphQL operation, with its digest.
      # @api private
      # @example required database table
      #    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
      #    ┃          graphql_operations         ┃
      #    ┣━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ id        ┃ primary key             ┃
      #    ┣━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ digest    ┃ varchar (index, unique) ┃
      #    ┣━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ name      ┃ varchar                 ┃
      #    ┣━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ body      ┃ text                    ┃
      #    ┗━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━┛
      class GraphqlOperation < ApplicationRecord::Domain::Api
        NAME_LENGTH_LIMIT = 256

        self.table_name = :graphql_operations
        self.primary_key = :id
        has_many :graphql_client_operations,
          foreign_key: :graphql_operation_id,
          primary_key: :id
        has_many :graphql_clients,
          through: :graphql_client_operations,
          foreign_key: :graphql_client_id,
          primary_key: :id
        has_many :graphql_index_references,
          foreign_key: :graphql_operation_id,
          dependent: :destroy,
          primary_key: :id
        has_many :graphql_index_entries,
          through: :graphql_index_references,
          foreign_key: :graphql_index_entry_id,
          primary_key: :id

        after_destroy :remove_orphaned_client_operations
        after_destroy :remove_orphaned_index_entries

        private

        def remove_orphaned_client_operations
          OrphanRemoval.remove_orphaned_client_operations
        end

        def remove_orphaned_index_entries
          OrphanRemoval.remove_orphaned_index_entries
        end
      end
    end
  end
end
