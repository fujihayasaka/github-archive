# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class RepositoryIssueTypeChange < Base
      extend T::Sig
      include GitHub::Memoizer
      include ResyncProjectsStrategy
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.RepositoryIssueTypeCreate\Z/,
          /github\.v1\.RepositoryIssueTypeUpdate\Z/,
          /github\.v1\.RepositoryIssueTypeDestroy\Z/,
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

      sig { override.returns(T::Boolean) }
      def valid_message?
        repository_id.present?
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
            filter: [
              { term: { "content.repository_id": repository_id } },
              { term: { "content.type": "Issue" } },
            ],
          },
        }
      end

      sig { override.returns(T::Array[Integer]) }
      memoize def project_ids_to_resync
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { returns(T.nilable(Integer)) }
      memoize private def repository_id
        @message.dig(:repository, :id)
      end
    end
  end
end
