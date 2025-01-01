# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          class Body < T::Struct
            # This is mostly modeled from the Elasticsearch Search API documentation:
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html#search-search-api-request-body
            #
            # But there are minor adjustments based on what the Elastomer Client library expects. See:
            # https://github.com/github/elastomer-client/blob/main/lib/elastomer_client/client/docs.rb

            const :_source, T.nilable(Source)
            const :docvalue_fields, T.nilable(T::Array[T.any(String, Field)])
            const :explain, T.nilable(T::Boolean)
            const :fields, T.nilable(T::Array[T.any(String, Field)])
            const :from, T.nilable(Integer)
            const :indices_boost, T.nilable(T::Array[IndicesBoost])
            const :knn, T.nilable(Knn)
            const :min_score, T.nilable(Float)
            const :pit, T.nilable(Pit)
            const :q, T.nilable(String)
            const :query, T.nilable(T::Hash[T.untyped, T.untyped])
            const :runtime_mappings, T.nilable(T::Array[RuntimeMappings])
            const :semantic, T.nilable(Semantic)
            const :seq_no_primary_term, T.nilable(T::Boolean)
            const :size, T.nilable(Integer)
            const :stats, T.nilable(T::Array[String])
            const :stored_fields, T.nilable(String)
            const :terminate_after, T.nilable(Integer)
            const :timeout, T.nilable(String)
            const :version, T.nilable(T::Boolean)

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                _source: _source&.to_hash,
                docvalue_fields: docvalue_fields&.map { _1.is_a?(Field) ? _1.to_hash : _1 },
                explain:,
                fields: fields&.map { _1.is_a?(Field) ? _1.to_hash : _1 },
                from:,
                indices_boost: indices_boost&.map(&:to_hash),
                knn: knn&.to_hash,
                min_score:,
                pit: pit&.to_hash,
                q:,
                query:,
                runtime_mappings: runtime_mappings&.map(&:to_hash),
                semantic:,
                seq_no_primary_term:,
                size:,
                stats:,
                stored_fields:,
                terminate_after:,
                timeout:,
                version:
              }.compact
            end
          end
        end
      end
    end
  end
end
