# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Delete
        # This is a struct representing the response from Elasticsearch deletes. Its self.from_es_response method can/should
        # be used to hydrate it before returning from a delete method call.
        class Response < T::Struct
          extend T::Sig

          class Result < T::Enum
            enums do
              Deleted = new("deleted")
              NotFound = new("not_found")
              Noop = new("noop")
            end
          end

          const :_index, String
          const :_type, T.nilable(String)
          const :_id, String
          const :_version, Integer
          const :_shards, Api::Response::Shards
          const :_seq_no, T.nilable(Integer)
          const :_primary_term, Integer
          const :error, T.nilable(Api::Response::FailureCause)
          const :forced_refresh, T.nilable(T::Boolean)
          const :result, T.nilable(Result)
          const :status, T.nilable(Integer)

          sig { params(response: T::Hash[T.untyped, T.untyped]).returns(Response) }
          def self.from_es_response(response)
            attrs = response.deep_symbolize_keys
            attrs[:_shards] = Api::Response::Shards.from_es_response(attrs[:_shards])
            attrs[:result] = Result.deserialize(attrs[:result])
            new(attrs)
          end

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              _index: _index,
              _type: _type,
              _id: _id,
              _version: _version,
              _shards: _shards.to_hash,
              _seq_no: _seq_no,
              _primary_term: _primary_term,
              forced_refresh:,
              result: result&.serialize,
              status:,
            }.with_indifferent_access
          end
        end
      end
    end
  end
end
