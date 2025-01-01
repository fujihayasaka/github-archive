# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class MilestoneDelete < Base
      extend T::Sig
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.MilestoneDelete\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Milestone.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        # In the case of deletes, we expect NOT to find the given milestone. If it is somehow still present, we should abort.
        !model.present?
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
                    "field_values.#{MemexProjectColumn::Milestone.value_name}.id": milestone_id
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
          # If we find the milestone field and it does in fact have our id (which it always should if we're targeting that id in the accompanying query),
          # we set the value to null to remove the milestone. Note that for now we don't remove all field metadata because other processors expect it to
          # be there. This will likely change in the future.
          #
          # If the field isn't found or the id doesn't match we `noop`. This shouldn't happen based on the query we're using with `update_by_query` but
          # we have it here just in case there is an unexpected race condition that affords us the opportunity to avoid unnecessary updating.
          source: """
            boolean field_removed = ctx._source.field_values.removeIf(f -> f.field_type == params.field_type);
            if (!field_removed) {
              ctx.op = 'noop';
            }
          """,
          params: {
            field_type: MemexProjectColumn::Milestone.data_type,
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
        message.dig(:milestone, :id)
      end

    end
  end
end
