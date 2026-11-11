# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    # This processor handles the destruction of IssueField records. It removes any references to the destroyed IssueField
    # from the field_values array in elasticsearch documents.
    # This exists because we explicitly keep IssueFields proactively indexed in documents for performance after the field
    # column is removed from the project. However, when the IssueField is destroyed, we can safely remove it from the index.
    # See packages/planning/app/models/memex_project_column/interface/indexable/processor/column_destroy.rb
    class IssueFieldDestroy < Base
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.IssueFieldDestroy\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        issue_field_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      # Prevent processing the message if the IssueField still exists
      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        issue_field.blank?
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          nested: {
            path: "field_values",
            query: {
              term: { "field_values.issue_field_id": issue_field_id, }
            }
          }
        }
      end

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def es_update
        Elastomer::Interfaces::Api::Request::Script.new(
          source: """
            boolean field_removed = ctx._source.field_values.removeIf(field -> field.issue_field_id == params.issue_field_id);
            if (!field_removed) {
              ctx.op = 'noop';
            }
          """,
          params: { issue_field_id: }
        )
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::UpdateByQuery::Response)
      end
      def update(es_client)
        body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query: es_query, script: es_update)
        params = Elastomer::Interfaces::Api::UpdateByQuery::Request::Params.new(
          refresh: Elastomer::Interfaces::Api::UpdateByQuery::Request::Params::Refresh::False
        )
        es_client.update_by_query(body, params)
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        []
      end

      sig { returns(T.nilable(IssueField)) }
      memoize private def issue_field
        IssueField.find_by(id: issue_field_id)
      end

      sig { returns(T.nilable(Integer)) }
      memoize private def issue_field_id
        @message.dig(:issue_field, :id)
      end
    end
  end
end
