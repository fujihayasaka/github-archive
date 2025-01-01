# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Update
        # This is a struct representing the response from Elasticsearch update requests. Its self.from_es_response method can/should
        # be used to hydrate it before returning from a method call.
        class Response < T::Struct
          extend T::Sig

          class Result < T::Enum
            enums do
              # created can be returned in the cases of upserts
              Created = new("created")
              Updated = new("updated")
              NotFound = new("not_found")
              Noop = new("noop")
            end
          end

          const :_index, String
          const :_type, T.nilable(String)
          const :_id, String
          const :_primary_term, Integer
          const :_shards, Api::Response::Shards
          const :_seq_no, Integer
          const :_version, Integer
          const :failures, T.nilable(T::Array[Api::Response::FailureCause])
          const :forced_refresh, T.nilable(T::Boolean)
          const :result, Result

          sig { params(response: T::Hash[T.untyped, T.untyped]).returns(Response) }
          def self.from_es_response(response)
            attrs = response.deep_symbolize_keys
            attrs[:failures] = attrs[:failures].map { Api::Response::FailureCause.from_es_response(_1) } if attrs[:failures]
            attrs[:result] = Result.deserialize(attrs[:result])
            attrs[:_shards] = Api::Response::Shards.from_es_response(attrs[:_shards])
            new(attrs)
          end

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              _id: _id,
              _index: _index,
              _primary_term: _primary_term,
              _shards: _shards.to_hash,
              _seq_no: _seq_no,
              _type: _type,
              _version: _version,
              forced_refresh:,
              result: result.serialize,
              failures: failures&.map(&:to_hash),
            }.with_indifferent_access
          end
        end
      end
    end
  end
end
