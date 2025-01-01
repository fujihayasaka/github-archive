# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          class Source < T::Struct
            extend T::Sig
            # This is modeled after field references in the Elasticsearch Search API documentation:
            #
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html

            const :excludes, T.nilable(T::Array[String])
            const :includes, T.nilable(T::Array[String])

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                excludes:,
                includes:,
              }.compact
            end
          end
        end
      end
    end
  end
end
