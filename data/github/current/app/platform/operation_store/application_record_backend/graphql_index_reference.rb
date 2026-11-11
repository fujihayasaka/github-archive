# typed: true
# frozen_string_literal: true

module Platform
  module OperationStore
    class ApplicationRecordBackend
      # A join between operation and the entries it depends on
      # @api private
      # @example required database table
      #    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
      #    ┃                graphql_index_references                        ┃
      #    ┣━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ id                    ┃ primary key                            ┃
      #    ┣━━━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ graphql_operation_id  ┃ foreign key                            ┃
      #    ┣━━━━━━━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
      #    ┃ graphql_index_entry   ┃ f-key (unique w/graphql_operation_id)  ┃
      #    ┗━━━━━━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
      class GraphqlIndexReference < ApplicationRecord::Domain::Api
        self.table_name = :graphql_index_references
        self.primary_key = :id
        belongs_to :graphql_index_entry, primary_key: :id
        belongs_to :graphql_operation, primary_key: :id
      end
    end
  end
end
