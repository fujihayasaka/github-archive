# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class ReviewersChange < Base
      extend T::Sig
      include ContentHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.PullRequestReviewRequest\Z/,
          /github\.v1\.PullRequestReviewSubmit\Z/,
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        PullRequest.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        content.present?
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_items_for_content.pluck(:memex_project_id).uniq.compact
      end

      # Query for all project items that match the pull request id
      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: [
              { term: { "content.id": pull_request_id, } },
              { term: { "content.repository_id": pull_request_repository_id } },
              { term: { "content.type": "PullRequest" } }
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
          field_class: MemexProjectColumn::Reviewers,
        )
      end

      sig { override.returns(T.nilable(PullRequest)) }
      memoize private def content
        PullRequest.find_by(id: pull_request_id)
      end

      sig { returns(T.nilable(Integer)) }
      private def pull_request_id
        @message.dig(:pull_request, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def pull_request_repository_id
        @message.dig(:repository, :id)
      end
    end
  end
end
