# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IssueUpdateIssueFieldValue < Base
      include GitHub::Memoizer
      include ContentHelpers

      abstract!

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.IssueUpdateIssueFieldValue\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        issue_field_id.present? && matching_issue_field_data_type? && issue_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        index.docs.count({ query: es_query }).dig("count") > 0
      end

      # Prevent processing the message if the canonical issue is not present. The issue field value can be nil if it was deleted.
      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        content.present? && issue_field.present?
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        items = project_items_for_content
        # In some cases, all project items have been deleted by the time we get to this stage of the pipeline, in which case
        # we should just abort.
        raise CanonicalDataMissingError unless items.present?

        issue_field = T.must(self.issue_field)
        items_by_memex_project_id = items.group_by(&:memex_project_id)

        es_client.bulk do |bulk|
          items_by_memex_project_id.each do |memex_project_id, items|
            memex_project = MemexProject.find_by(id: memex_project_id)
            next unless memex_project.present?

            # If the project has a different owner than the issue field, we will return early as issue fields are not
            # supported cross-organization yet.
            memex_project_column = MemexProjectColumn.build_readonly_issue_field(memex_project:, issue_field:)
            next unless memex_project_column.present?

            field = T.must(memex_project_column.to_field)

            items.each do |project_item|
              bulk.update(
                { script: field.elasticsearch_field_value_update_script(project_item).to_hash },
                { _id: project_item.id, routing: project_item.memex_project_id, retry_on_conflict: 3 }
              )
            end
          end
        end
      end

      # Issues are the only content type that can contain issue fields.
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
        Issue.find_by(id: issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { returns(T.nilable(Integer)) }
      private def issue_id
        @message.dig(:issue_id)
      end

      sig { returns(T.nilable(Integer)) }
      private def issue_field_id
        @message.dig(:issue_field, :id)
      end

      sig { returns(T.nilable(IssueField)) }
      memoize private def issue_field
        IssueField.find_by(id: issue_field_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { returns(T.nilable(Symbol)) }
      private def issue_field_data_type
        @message.dig(:issue_field, :data_type)&.to_sym&.downcase
      end

      sig { returns(T::Boolean) }
      def matching_issue_field_data_type?
        field_class.data_type == issue_field_data_type
      end

      # The IssueField class for the specific field type being processed. This field class is used to ensure
      # messages processed have the same data type as the issue field being updated. Without this, we could
      # accidentally process messages for the wrong field type and result in Elasticsearch errors because the
      # Elasticsearch mapping does not yet exist for a new data type.
      #
      # Example
      #
      #   sig { override.returns(T.class_of(MemexProjectColumn::Field::IssueField::Base)) }
      #   private def field_class
      #     MemexProjectColumn::Field::IssueField::Text
      #   end
      sig { abstract.returns(T.class_of(MemexProjectColumn::Field::IssueField::Base)) }
      private def field_class; end
    end
  end
end
