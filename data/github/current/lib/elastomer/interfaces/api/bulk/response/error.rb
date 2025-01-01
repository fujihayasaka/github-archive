# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Bulk
        module Response
          class Error < T::Struct
            extend T::Sig

            const :index, T.nilable(String)
            const :index_uuid, T.nilable(String)
            const :reason, T.nilable(String)
            const :shard, T.nilable(Integer)
            const :type, String

            sig { params(response: T::Hash[String, T.untyped]).returns(Error) }
            def self.from_es_response(response)
              new(
                index: response["index"],
                index_uuid: response["index_uuid"],
                reason: response["reason"],
                shard: response["shard"]&.to_i,
                type: response["type"]
              )
            end

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                index:,
                index_uuid:,
                reason:,
                shard:,
                type:,
              }
            end
          end
        end
      end
    end
  end
end
