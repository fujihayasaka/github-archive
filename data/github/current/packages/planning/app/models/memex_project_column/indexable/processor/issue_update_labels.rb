# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class IssueUpdateLabels < Base
      include GitHub::Memoizer
      include ContentHelpers
      extend T::Sig

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.IssueUpdateLabel\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        content.present?
      end

      sig { override.returns(T.nilable(T.any(Issue, PullRequest))) }
      memoize private def content
        pull_request_id ? PullRequest.find_by(id: pull_request_id) : Issue.find_by(id: issue_id)
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: [
              { term: { "content.id": content_id, } },
              { term: { "content.type": content_type } }
            ]
          }
        }
      end

      sig do override
        .params(es_client: ElasticsearchClient)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        bulk_update_field_values_for_content(
          es_client,
          field_class: MemexProjectColumn::Labels,
        )
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_items_for_content.map(&:memex_project_id).uniq.compact
      end

      sig { returns(Integer) }
      private def content_id
        T.must(pull_request_id || issue_id)
      end

      sig { returns(String) }
      private def content_type
        return "PullRequest" if pull_request_id
        "Issue"
      end

      sig { returns(T.nilable(Integer)) }
      private def pull_request_id
        @message.dig(:pull_request, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def issue_id
        @message.dig(:issue, :id)
      end

      sig { returns(Integer) }
      private def repository_id
        @message.dig(:repository, :id)
      end
    end
  end
end
