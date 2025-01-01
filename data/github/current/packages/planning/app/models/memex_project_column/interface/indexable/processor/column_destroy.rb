# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class ColumnDestroy < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex.v1\.MemexProjectColumnDestroy\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        MemexProjectColumn.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        # We do not process the removal of IssueFields here because we keep them proactively indexed until the IssueField itself
        # is destroyed. See IssueFieldDestroy processor packages/planning/app/models/memex_project_column/interface/indexable/processor/issue_field_destroy.rb
        !issue_field? && field_id.present? && project_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.docs.count({ query: es_query }, routing: project_id)["count"] > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        # Note that our terminology is a bit confusing in the case of destroys. To successfully pass through the canonical
        # data gate, we need to verify that the conditions are as we expect for a destroy -- in this case, that the column
        # has in fact been deleted.
        !model.present?
      end

      sig { returns(T.nilable(MemexProjectColumn)) }
      memoize private def model
        MemexProjectColumn.find_by(id: field_id)
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: [
              { term: { "memex_project_id": project_id } },
              {
                nested: {
                  path: "field_values",
                  query: {
                    bool: {
                      filter: { term: { "field_values.field_id": field_id } },
                    }
                  }
                }
              }
            ]
          }
        }
      end

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def es_update
        Elastomer::Interfaces::Api::Request::Script.new(
          source: "ctx._source.field_values.removeIf(f -> f.field_id == params.field_id);",
          params: {
            field_id: field_id
          }
        )
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::UpdateByQuery::Response)
      end
      def update(es_client)
        body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query: es_query, script: es_update)
        es_client.update_by_query(body)
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        [T.must(project_id)]
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        []
      end

      sig { returns(T.nilable(Integer)) }
      private def field_id
        message.dig(:memex_project_column, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def issue_field_id
        message.dig(:memex_project_column, :issue_field_id)
      end

      sig { returns(T::Boolean) }
      private def issue_field?
        issue_field_id&.positive? || false
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        message.dig(:memex_project, :id)
      end
    end
  end
end
