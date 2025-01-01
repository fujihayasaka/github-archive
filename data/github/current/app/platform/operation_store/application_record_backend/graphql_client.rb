# typed: true
# frozen_string_literal: true

module Platform
  module OperationStore
    class ApplicationRecordBackend
      # A client application for this GraphQL system.
      # @api private
      # @example required database table
      #    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
      #    ┃      graphql_clients                       ┃
      #    ┣━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ id     ┃  primary key                      ┃
      #    ┣━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ name   ┃ varchar (index, non-null, unique) ┃
      #    ┗━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
      class GraphqlClient < ApplicationRecord::Domain::Api
        self.table_name = :graphql_clients
        self.primary_key = :id
        has_many :graphql_client_operations,
          foreign_key: :graphql_client_id,
          dependent: :destroy,
          primary_key: :id

        has_many :graphql_operations,
          through: :graphql_client_operations,
          foreign_key: :graphql_operation_id,
          primary_key: :id

        after_destroy :remove_orphaned_operations
        after_destroy :remove_orphaned_index_entries

        validates :name, format: {
          without: Regexp.new(Regexp.escape(GraphQL::Pro::OperationStore::OPERATION_ID_SEPARATOR)),
          message: "may not include #{GraphQL::Pro::OperationStore::OPERATION_ID_SEPARATOR}, which is reserved for operation_id values.",
        }

        private

        def remove_orphaned_operations
          OrphanRemoval.remove_orphaned_operations
        end

        def remove_orphaned_index_entries
          OrphanRemoval.remove_orphaned_index_entries
        end

      end
    end
  end
end
