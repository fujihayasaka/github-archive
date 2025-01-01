# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Response
        class Shards < T::Struct
          # This class is used to represent the shards response from the Elasticsearch API. See for example:
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-index_.html#docs-index-api-response-body
          extend T::Sig

          # How many shard copies (primary and replica shards) the operation was executed on.
          const :total, Integer
          # The (optional) number of shard copies the operation skipped. This can be 0 or more for search operations but
          # may otherwise be omitted.
          const :skipped, T.nilable(Integer)
          # The number of shard copies the operation succeeded on. When the operation is successful, this value is >= 1.
          const :successful, Integer
          # The number of shard copies the operation failed on. When the operation is successful, this value is 0.
          const :failed, Integer
          # The failure causes for the operation. When the operation is successful, this is usually not present, but
          # may be an empty array in some cases.
          const :failures, T.nilable(T::Array[FailureCause])

          sig { params(response: T::Hash[T.untyped, T.untyped]).returns(Shards) }
          def self.from_es_response(response)
            new(response.deep_symbolize_keys)
          end

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              total:,
              successful:,
              failed:,
            }
          end
        end
      end
    end
  end
end
