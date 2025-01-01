# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          class Pit < T::Struct
            # This is modeled after field references in the Elasticsearch Search API documentation:
            #
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html

            const :id, String
            const :keep_alive, T.nilable(String)

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                id:,
                keep_alive:,
              }.compact
            end
          end
        end
      end
    end
  end
end
