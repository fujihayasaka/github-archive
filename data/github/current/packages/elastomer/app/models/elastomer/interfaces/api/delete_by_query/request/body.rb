# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module DeleteByQuery
        module Request
          # A struct representing the possible body attributes passed into an delete_by_query method. Here is an example
          # of default usage:
          #
          #  delete_by_query(Body.new(query: { term: { foo: "bar" } }), <Params>)
          #
          # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-delete-by-query.html#docs-delete-by-query-api-request-body
          class Body < T::Struct
            const :query, T::Hash[Symbol, T.untyped]

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              { query: }
            end
          end
        end
      end
    end
  end
end
