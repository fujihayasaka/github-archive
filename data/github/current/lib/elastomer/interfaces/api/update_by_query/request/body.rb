# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module UpdateByQuery
        module Request
          # A struct representing the possible body attributes passed into an update_by_query method. Here is an example
          # of default usage:
          #
          #  update_by_query(Body.new(query: { term: { foo: "bar" } }), <Params>)
          #
          # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update-by-query.html#docs-update-by-query-api-request-body for more detail.
          class Body < T::Struct
            extend T::Sig

            prop :query, T::Hash[Symbol, T.untyped]
            prop :script, Api::Request::Script

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                query:,
                script: script.to_hash,
              }
            end
          end
        end
      end
    end
  end
end
