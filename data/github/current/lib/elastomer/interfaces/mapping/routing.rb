# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      # Used to require that documents are indexed with a value that will route the document to a specific shard.
      #
      # For an overview of how shards work in Elasticsearch, see:
      # https://github.com/github/projects-backend/blob/main/docs/initiatives/memex-without-limits/understanding-elasticsearch-infrastructure.md
      #
      # For more details on routing, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-routing-field.html
      class Routing < T::Struct
        const :required, T::Boolean, default: true

        sig { returns(T::Hash[Symbol, T::Boolean]) }
        def to_hash
          {
            required: required
          }
        end
      end
    end
  end
end
