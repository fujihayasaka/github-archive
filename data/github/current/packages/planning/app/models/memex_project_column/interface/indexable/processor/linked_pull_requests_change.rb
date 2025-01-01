# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    # Updates the list of linked pull requests
    # on all memex project items representing a given issue
    # when a pull request is added to/removed from the issue.
    class LinkedPullRequestsChange < Base
      include GitHub::Memoizer
      include ContentHelpers

      # A list of [issue_id, repository_id] pairs that identify issues that we intentionally ignore in this processor.
      #
      # Use of this constant is a temporary measure that should be addressed more comprehensively in
      # https://github.com/github/projects-platform/issues/2495.
      DISALLOWED_REFERENCES = T.let(
        [
          # https://github.com/google/it-cert-automation-practice/issues/1, whose `close_issue_reference` association
          # regularly times out, thereby causing head of line blocking. For more details see:
          # https://github.com/github/projects-platform/issues/2495
          [541051420, 228683419]
        ],
        T::Array[[Integer, Integer]]
      )

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.CloseIssueReferenceConnected\Z/,
          /github\.v1\.CloseIssueReferenceDisconnected\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        !!(
          issue_id.present? &&
          issue_repository_id.present? &&
          !DISALLOWED_REFERENCES.include?([issue_id, issue_repository_id])
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

      # Find all items with the content_id matching the Issue
      # Update the list of linked_pull_requests to include the new pull request
      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        bulk_update_field_values_for_content(
          es_client,
          field_class: MemexProjectColumn::Field::LinkedPullRequests,
        )
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_items_for_content.pluck(:memex_project_id).uniq
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [content, *project_items_for_content]
      end

      # Query for all project items that match the issue id
      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: [
              { term: { "content.id": issue_id } },
              { term: { "content.repository_id": issue_repository_id } },
              { term: { "content.type": "Issue" } }
            ]
          }
        }
      end

      sig { override.returns(T.nilable(Issue)) }
      memoize private def content
        Issue.find_by(id: issue_id)
      end

      sig { returns(T.nilable(Integer)) }
      private def issue_id
        @message.dig(:issue, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def issue_repository_id
        @message.dig(:issue_repository, :id)
      end
    end
  end
end
