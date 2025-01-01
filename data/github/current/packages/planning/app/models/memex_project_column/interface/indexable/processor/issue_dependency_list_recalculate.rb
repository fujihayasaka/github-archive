# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IssueDependencyListRecalculate < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.IssueDependencyListRecalculate\Z/,
        ]
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        issue_id.present? && repository_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        issue.present? && issue_dependency_list.present?
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::UpdateByQuery::Response)
      end
      def update(es_client)
        script = Elastomer::Interfaces::Api::Request::Script.new(
          source: """
            ctx._source.content.open_blocked_by_count = params.open_blocked_by_count;
            ctx._source.content.open_blocking_count = params.open_blocking_count;
          """,
          params: {
            open_blocked_by_count: blocked_by_count,
            open_blocking_count: blocking_count,
          }
        )

        body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(
          query: es_query,
          script: script
        )

        es_client.update_by_query(body)
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        # Query Elasticsearch to find which projects contain this issue
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [issue].compact
      end

      sig { returns(T.nilable(Issue)) }
      memoize private def issue
        Issue.find_by(id: issue_id, repository_id: repository_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { returns(T.nilable(IssueDependencyList)) }
      memoize private def issue_dependency_list
        IssueDependencyList.find_by(issue_id: issue_id, repository_id: repository_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      # Query for all project items that match the issue id and repository
      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: [
              { term: { "content.id": issue_id } },
              { term: { "content.type": "Issue" } }
            ]
          }
        }
      end

      sig { returns(T.nilable(Integer)) }
      private def issue_id
        @message.dig(:issue, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def repository_id
        @message.dig(:repository, :id)
      end

      sig { returns(Integer) }
      private def blocked_by_count
        issue_dependency_list&.blocked_by || 0
      end

      sig { returns(Integer) }
      private def blocking_count
        issue_dependency_list&.blocking || 0
      end

      # Include helper to get project IDs from Elasticsearch
      include SpecialFieldProcessorHelpers
    end
  end
end
