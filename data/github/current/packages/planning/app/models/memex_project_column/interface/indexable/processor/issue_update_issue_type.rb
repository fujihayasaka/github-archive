# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IssueUpdateIssueType < Base
      include GitHub::Memoizer
      include ContentHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.IssueUpdateIssueType\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      # Prevent processing the message if the issue_id is not present, as it is required to build the query.
      sig { override.returns(T::Boolean) }
      def valid_message?
        issue_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        index.docs.count({ query: es_query }).dig("count") > 0
      end

      # Prevent processing the message if the canonical issue is not present. The issue type can be nil if it was deleted.
      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        content.present?
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        bulk_update_field_values_for_content(
          es_client,
          field_class: MemexProjectColumn::Field::IssueType,
        )
      end

      # Issues are the only content type that can contain issue types.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: [
              { term: { "content.type": "Issue" } },
              { term: { "content.id": issue_id } }
            ]
          }
        }
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_items_for_content.collect(&:memex_project_id).uniq
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [content, *project_items_for_content]
      end

      sig { override.returns(T.nilable(Issue)) }
      memoize private def content
        Issue.find_by(id: issue_id)
      end

      sig { returns(T.nilable(Integer)) }
      private def issue_id
        @message.dig(:issue, :id)
      end

      sig { returns(T.nilable(Repository)) }
      memoize private def repository
        content&.repository
      end

      sig { returns(T.nilable(IssueType)) }
      memoize private def issue_type
        content&.issue_type
      end
    end
  end
end
