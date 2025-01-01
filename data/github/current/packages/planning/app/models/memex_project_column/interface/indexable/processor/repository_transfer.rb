# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class RepositoryTransfer < Base
      include GitHub::Memoizer
      include ResyncProjectsStrategy
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.repositories\.v1\.Transferred\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        index.count_all({ query: es_query }) > 0
      end

      # The underlying repository does not need to exist in the database for this message to be valid, only need to
      # know if any documents exist in Elasticsearch reference the repository.
      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        true
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      private def es_query
        {
          bool: {
            filter: {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.#{MemexProjectColumn::Field::Repository.value_name}.id": repository_id
                  }
                }
              }
            }
          }
        }
      end

      sig { override.returns(T::Array[Integer]) }
      memoize def project_ids_to_resync
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        []
      end

      sig { returns(Integer) }
      memoize private def repository_id
        @message.dig(:repository_id)
      end
    end
  end
end
