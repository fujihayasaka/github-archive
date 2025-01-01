# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IssueTypeDestroy < Base
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      BATCH_SIZE = 1000

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.IssueTypeDestroy\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      # Prevent processing the message if the issue_type_id is not present, as it is required to build the query.
      sig { override.returns(T::Boolean) }
      def valid_message?
        issue_type_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      # Prevent processing the message if the IssueType still exists, as we do not want to clear any issue types that
      # still exist.
      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        issue_type.blank?
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.#{MemexProjectColumn::Field::IssueType.value_name}.id": issue_type_id,
                  }
                }
              }
            }
          }
        }
      end

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def es_update
        Elastomer::Interfaces::Api::Request::Script.new(
          source: """
            boolean field_removed = ctx._source.field_values.removeIf(field -> field.containsKey(params.value_name));
            if (!field_removed) {
              ctx.op = 'noop';
            }
          """,
          params: {
            issue_type_id:,
            value_name: MemexProjectColumn::Field::IssueType.value_name,
          }
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

      sig { returns(T.nilable(IssueType)) }
      memoize private def issue_type
        IssueType.find_by(id: issue_type_id)
      end

      sig { returns(T.nilable(Integer)) }
      memoize private def issue_type_id
        @message.dig(:issue_type, :id)
      end
    end
  end
end
