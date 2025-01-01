# typed: strict
# frozen_string_literal: true

require_relative "hits/hit"
require_relative "hits/total"

module Elastomer
  module Interfaces
    module Api
      module Response
        class Hits < T::Struct
          extend T::Sig

          const :total, Total
          const :max_score, T.nilable(Float)
          const :hits, T::Array[Hit]

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              total: total.to_hash,
              max_score: max_score,
              hits: hits.map(&:to_hash)
            }
          end

          sig { params(response: T::Hash[String, T.untyped]).returns(Hits) }
          def self.from_es_response(response)
            new(
              total: Total.from_es_response(response["total"]),
              max_score: response["max_score"],
              hits: response["hits"].map { |hit| Hit.from_es_response(hit) }
            )
          end
        end
      end
    end
  end
end
