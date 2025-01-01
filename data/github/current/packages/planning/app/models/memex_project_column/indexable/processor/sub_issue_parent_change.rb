# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class SubIssueParentChange < Base
      extend T::Sig
      include ContentHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.SubIssueAdd\Z/,
          /github\.v1\.SubIssueRemove\Z/,
        ]
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        target_issue_id.present? && source_issue_id.present?
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
        .params(es_client: ElasticsearchClient)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        bulk_update_field_values_for_content(es_client, field_class: MemexProjectColumn::ParentIssue)
      end


      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_items_for_content.pluck(:memex_project_id)&.uniq || []
      end

      sig { override.returns(T.nilable(Issue)) }
      private def content
        Issue.find_by(id: target_issue_id)
      end

      # Query for all project items that match the target issue id
      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: [
              { term: { "content.id": target_issue_id } },
              { term: { "content.type": "Issue" } }
            ]
          }
        }
      end

      sig { returns(T.nilable(Integer)) }
      private def target_issue_id
        @message.dig(:target_issue, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def source_issue_id
        @message.dig(:source_issue, :id)
      end
    end
  end
end
