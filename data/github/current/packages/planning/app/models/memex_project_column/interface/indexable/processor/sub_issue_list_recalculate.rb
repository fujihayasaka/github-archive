# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class SubIssueListRecalculate < Base
      include ContentHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.SubIssueListRecalculate\Z/,
        ]
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        source_issue_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        content.present?
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        bulk_update_field_values_for_content(
          es_client,
          field_class: MemexProjectColumn::Field::SubIssuesProgress
        )
      end


      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_items_for_content.pluck(:memex_project_id)&.uniq || []
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [content, *project_items_for_content]
      end

      sig { override.returns(T.nilable(Issue)) }
      private def content
        Issue.find_by(id: source_issue_id)
      end

      # Query for all project items that match the source issue id
      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: [
              { term: { "content.id": source_issue_id } },
              { term: { "content.type": "Issue" } }
            ]
          }
        }
      end

      sig { returns(T.nilable(Integer)) }
      private def source_issue_id
        @message.dig(:source_issue, :id)
      end
    end
  end
end
