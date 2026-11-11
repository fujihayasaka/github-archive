# typed: true
# frozen_string_literal: true

module Platform
  module OperationStore
    class ApplicationRecordBackend
      # An object in a GraphQL schema which may be used for an operation:
      # - Type
      # - Field
      # - Argument (or input_field)
      # - Directive
      # - EnumValue
      #
      # @api private
      # @example required database table
      #    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
      #    ┃                graphql_index_entries                           ┃
      #    ┣━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ id                    ┃ primary key                            ┃
      #    ┣━━━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ name                  ┃ varchar (index, unique)                ┃
      #    ┣━━━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ last_used_at          ┃ datetime (index)                       ┃
      #    ┗━━━━━━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
      class GraphqlIndexEntry < ApplicationRecord::Domain::Api
        self.table_name = :graphql_index_entries
        self.primary_key = :id
        has_many :graphql_index_references,
          foreign_key: :graphql_index_entry_id,
          primary_key: :id

        has_many :graphql_operations,
          through: :graphql_index_references,
          foreign_key: :graphql_operation_id,
          primary_key: :id
      end
    end
  end
end
