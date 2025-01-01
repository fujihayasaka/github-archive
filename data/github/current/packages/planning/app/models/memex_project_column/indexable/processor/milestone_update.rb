# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class MilestoneUpdate < Base
      extend T::Sig
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.MilestoneUpdate\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Milestone.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        # We currently only care about milestone updates if the title has changed.
        message.dig(:milestone, :title) != message.dig(:previous_title)
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        model.present?
      end

      sig { returns(T.nilable(Milestone)) }
      memoize private def model
        Milestone.find_by(id: milestone_id)
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
                    "field_values.milestone_value.id": milestone_id
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
            def field = ctx._source.field_values.find(f -> f.field_type == params.field_type);
            if (field[params.value_name].title == params.update_value) {
              ctx.op = 'noop';
            } else {
              field[params.value_name].title = params.update_value;
            }
          """,
          params: {
            field_type: MemexProjectColumn::Milestone.data_type,
            value_name: MemexProjectColumn::Milestone.value_name,
            update_value: T.must(model).title,
            id: milestone_id
          }
        )
      end

      sig do override
        .params(es_client: ElasticsearchClient)
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
        # Note that, unlike some other processors, we fetch project ids from Elasticsearch rather than from MySQL.
        # Querying for all issues and draft issues with a particular milestone is an expensive operation that spans
        # multiple clusters. It is not yet apparent that fetching from Elasticsearch is an inferior approach. We'll
        # revisit this implementation if that changes.
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { returns(Integer) }
      memoize private def milestone_id
        @message.dig(:milestone, :id)
      end

    end
  end
end
