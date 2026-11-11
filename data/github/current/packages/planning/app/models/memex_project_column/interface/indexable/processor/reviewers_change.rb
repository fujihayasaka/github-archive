# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class ReviewersChange < Base
      include ContentHelpers

      # A list of pull request IDs that we intentionally ignore in this processor.
      #
      # Use of this constant is a temporary measure that should be addressed more comprehensively in
      # https://github.com/github/memex/issues/21002.
      DISALLOWED_PULL_REQUEST_IDS = T.let(
        [
          # Pull request whose review request processing regularly times out,
          # thereby causing head of line blocking.
          1094214744,
        ],
        T::Array[Integer],
      )

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.PullRequestReviewRequest\Z/,
          /github\.v1\.PullRequestReviewSubmit\Z/,
        ]
      end

      sig { override.returns(T::Set[String]) }
      def self.tracked_associations
        Set.new(%w[PullRequestReview ReviewRequest])
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        PullRequest.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        !!(
          pull_request_id.present? &&
          pull_request_repository_id.present? &&
          !DISALLOWED_PULL_REQUEST_IDS.include?(pull_request_id)
        )
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

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [content, *project_items_for_content]
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
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        bulk_update_field_values_for_content(
          es_client,
          field_class: MemexProjectColumn::Field::Reviewers,
        )
      end

      sig { override.returns(T.nilable(PullRequest)) }
      memoize public def content
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
