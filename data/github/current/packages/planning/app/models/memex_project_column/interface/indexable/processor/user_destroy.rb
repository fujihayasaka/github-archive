# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class UserDestroy < Base
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      BATCH_SIZE = 1000

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.UserDestroy\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        User.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        model.blank?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
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

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def es_update
        Elastomer::Interfaces::Api::Request::Script.new(
          # If the user is found in the assignees or reviewers field values, remove them.
          # If the given field is empty after removing the user, remove the field entirely.
          # We start with the assumption of noop, and only change to index if we actually need to update the document.
          source: """
            ctx.op = 'noop';
            def assignees = ctx._source.field_values.find(f -> f.field_type == params.assignees_field_type);
            if (assignees != null && assignees[params.assignees_value_key].removeIf(val -> val[params.assignees_id_key] == params.user_id)) {
              ctx.op = 'index';
              if (assignees[params.assignees_value_key].isEmpty()) {
                ctx._source.field_values.removeIf(f -> f == assignees);
              }
            }
            def reviewers = ctx._source.field_values.find(f -> f.field_type == params.reviewers_field_type);
            if (reviewers != null && reviewers[params.reviewers_value_key].removeIf(val -> val[params.reviewers_id_key] == params.user_id && val[params.reviewers_type_key] == params.reviewers_type_value)) {
              ctx.op = 'index';
              if (reviewers[params.reviewers_value_key].isEmpty()) {
                ctx._source.field_values.removeIf(f -> f == reviewers);
              }
            }
          """,
          params: {
            "user_id": user_id,
            # assignees update
            "assignees_field_type": MemexProjectColumn::Field::Assignees.data_type,
            "assignees_value_key": MemexProjectColumn::Field::Assignees.value_name,
            "assignees_id_key": "id",

            # reviewers update
            "reviewers_field_type": MemexProjectColumn::Field::Reviewers.data_type,
            "reviewers_value_key": MemexProjectColumn::Field::Reviewers.value_name,
            "reviewers_id_key": "actor_id",
            "reviewers_type_key": "actor_type",
            "reviewers_type_value": "User", # ReviewRequest model uses type as plain strings, no constants exist
          }
        )
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          "bool": {
            "filter": {
              "nested": {
                "path": "field_values",
                "query": {
                  "bool": {
                    "should": [
                      { "term": { "field_values.#{MemexProjectColumn::Field::Assignees.value_name}.id": user_id } },
                      { "term": { "field_values.#{MemexProjectColumn::Field::Reviewers.value_name}.actor_id": user_id } },
                    ]
                  }
                }
              }
            }
          }
        }
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        []
      end

      sig { returns(T.nilable(User)) }
      memoize private def model
        User.unscoped.find_by(id: user_id)
      end

      sig { returns(Integer) }
      memoize private def user_id
        @message.dig(:user, :id) || @message.dig(:account, :id)
      end
    end
  end
end
