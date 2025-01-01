# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          class RuntimeMappings < T::Struct
            extend T::Sig
            # This is modeled after field references in the Elasticsearch Search API documentation:
            #
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html

            const :field_name, String
            const :type, String
            const :script, T.nilable(String)

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_hash
              {
                field_name:,
                type:,
                script:,
              }.compact
            end
          end
        end
      end
    end
  end
end
