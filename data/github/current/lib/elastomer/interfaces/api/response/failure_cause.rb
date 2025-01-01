# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Response
        class FailureCause < T::Struct
          # When an Elasticsearch response includes a failure, it will have a `cause` array that collects the 1 or more
          # failure causes. Each cause will have the attributes modeled here.
          #
          # Unfortunately, the Elasticsearch documentation does not formally document the structure of the `cause` items,
          # so there is no link to reference.
          extend T::Sig
          const :type, String
          const :reason, T.any(String, T::Hash[T.untyped, T.untyped])
          const :index_uuid, T.nilable(String)
          const :shard, String
          const :index, String

          sig { params(response: T::Hash[T.untyped, T.untyped]).returns(FailureCause) }
          def self.from_es_response(response)
            new(response.deep_symbolize_keys)
          end

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              type:,
              reason:,
              index_uuid:,
              shard:,
              index:,
            }
          end
        end
      end
    end
  end
end
