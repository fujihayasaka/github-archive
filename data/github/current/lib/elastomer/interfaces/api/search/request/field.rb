# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          class Field < T::Struct
            # This is modeled after field references in the Elasticsearch Search API documentation:
            #
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html

            const :field, String
            const :format, T.nilable(String)

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                field:,
                format:,
              }.compact
            end
          end
        end
      end
    end
  end
end
