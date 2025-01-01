# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class LabelDelete < Base
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.LabelDelete\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        model.blank?
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
                    "field_values.#{MemexProjectColumn::Field::Labels.value_name}.id": label_id
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
          # Assume a noop, which we'll overrwrite if we do apply a mutation. We first check to see if the field exists.
          # If so, we try to remove the label value. If we do remove it, check if the field is no entirely empty,
          # in which case we should remove the field entirely from the index.
          source: """
            ctx.op = 'noop';
            def labels_field = ctx._source.field_values.find(field -> field.containsKey(params.value_name));
            if (labels_field != null) {
              boolean label_removed = labels_field[params.value_name].removeIf(label -> label.id == params.label_id);
              if (label_removed) {
                ctx.op = 'index';
                if (labels_field[params.value_name].isEmpty()) {
                  ctx._source.field_values.removeIf(field -> field == labels_field);
                }
              }
            }
          """,
          params: {
            label_id:,
            value_name: MemexProjectColumn::Field::Labels.value_name
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
        # Note that, unlike some other processors, we fetch project ids from Elasticsearch rather than from MySQL.
        # Querying for all issues and draft issues with a particular label is an expensive operation that spans
        # multiple clusters. It is not yet apparent that fetching from Elasticsearch is an inferior approach. We'll
        # revisit this implementation if that changes.
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        []
      end

      sig { returns(Integer) }
      memoize private def label_id
        @message.dig(:label, :label_id)
      end

    end
  end
end
