# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Bulk
        module Response
          class ItemResult < T::Struct
            extend T::Sig

            class Result < T::Enum
              enums do
                Created = new("created")
                Deleted = new("deleted")
                Updated = new("updated")
                Noop = new("noop")
              end
            end

            const :_id, Integer
            const :_index, String
            const :_primary_term, T.nilable(Integer)
            const :_seq_no, T.nilable(Integer)
            const :_shards, T.nilable(Api::Response::Shards)
            const :_version, T.nilable(Integer)
            const :error, T.nilable(Error)
            const :result, T.nilable(Result)
            const :status, Integer

            sig { params(response: T::Hash[String, T.untyped]).returns(ItemResult) }
            def self.from_es_response(response)
              new(
                _id: response["_id"].to_i,
                _index: response["_index"],
                _primary_term: response["_primary_term"],
                _seq_no: response["_seq_no"],
                _shards: response["_shards"] ? Api::Response::Shards.from_es_response(response["_shards"]) : nil,
                _version: response["_version"],
                error: response["error"] ? Error.from_es_response(response["error"]) : nil,
                result: response["result"] ? Result.deserialize(response["result"]) : nil,
                status: response["status"]
              )
            end

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                _id: _id,
                _index: _index,
                _primary_term: _primary_term,
                _seq_no: _seq_no,
                _shards: _shards&.to_hash,
                _version: _version,
                error: error&.to_hash,
                result: result&.serialize,
                status:,
              }
            end
          end
        end
      end
    end
  end
end
