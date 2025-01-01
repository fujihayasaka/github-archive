# typed: strict
# frozen_string_literal: true

require "elastomer/interfaces/api/response/hits"
require "elastomer/interfaces/api/response/shards"

module Elastomer
  module Interfaces
    module Api
      module Search
        class Response < T::Struct
          extend T::Sig

          const :_scroll_id, T.nilable(String)
          const :_shards, Api::Response::Shards
          const :hits, Api::Response::Hits
          const :timed_out, T::Boolean
          const :took, Integer

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              _scroll_id: _scroll_id,
              _shards: _shards.to_hash,
              hits: hits.to_hash,
              timed_out:,
              took:,
            }
          end

          sig { params(response: T::Hash[String, T.untyped]).returns(Response) }
          def self.from_es_response(response)
            new(
              _scroll_id: response["_scroll_id"],
              _shards: Api::Response::Shards.from_es_response(response["_shards"]),
              hits: Api::Response::Hits.from_es_response(response["hits"]),
              timed_out: response["timed_out"],
              took: response["took"],
            )
          end
        end
      end
    end
  end
end
