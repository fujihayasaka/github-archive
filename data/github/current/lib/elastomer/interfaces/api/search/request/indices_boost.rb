# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          class IndicesBoost < T::Struct
            extend T::Sig
            # This is modeled after field references in the Elasticsearch Search API documentation:
            #
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html

            const :index, String
            const :boost_value, Float

            sig { returns(T::Hash[String, Float]) }
            def to_hash
              { index => boost_value }
            end
          end
        end
      end
    end
  end
end
