# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class LabelUpdate < Base
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.LabelUpdate\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        if any_match_helper_enabled?
          @es_client.any_match?(es_query)
        else
          @index.count_all({ query: es_query }) > 0
        end
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        model.present?
      end

      sig { returns(T.nilable(Label)) }
      memoize private def model
        Label.find_by(id: label_id)
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
                    "field_values.labels_value.id": label_id
                  }
                }
              }
            }
          }
        }
      end

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def es_update
        label = T.must(model)
        Elastomer::Interfaces::Api::Request::Script.new(
          source: """
            def field = ctx._source.field_values.find(f -> f.field_type == params.field_type);
            def label = field[params.value_name].find(val -> val.id == params.id);
            label.name = params.update_value;
          """,
          params: {
            field_type: MemexProjectColumn::Field::Labels.data_type,
            value_name: MemexProjectColumn::Field::Labels.value_name,
            update_value: label.name,
            id: label_id,
          }
        )
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::UpdateByQuery::Response)
      end
      def update(es_client)
        body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query: es_query, script: es_update)
        params = Elastomer::Interfaces::Api::UpdateByQuery::Request::Params.new(refresh: update_by_query_refresh_strategy)
        es_client.update_by_query(body, params)
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        # Note that, unlike some other processors, we fetch project ids from Elasticsearch rather than from MySQL.
        # Querying for all issues and draft issues with a particular label is an expensive operation that spans
        # multiple clusters. It is not yet apparent that fetching from Elasticsearch is an inferior approach. We'll
        # revisit this implementation if that changes.
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [model]
      end

      sig { returns(Integer) }
      memoize private def label_id
        @message.dig(:label, :label_id)
      end
    end
  end
end
