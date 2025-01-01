# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class TeamRename < Base
      extend T::Sig
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.TeamRename\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Team.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        return false if team_id.blank?

        # confirm this message includes a team name change
        message.dig(:previous_name) != @message.dig(:current_name)
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        model.present?
      end

      sig { returns(T.nilable(Team)) }
      memoize private def model
        Team.find_by(id: team_id)
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      private def es_query
        {
          bool: {
            filter: {
              nested: {
                path: "field_values",
                query: {
                  bool: {
                    filter: [
                      { term: { "field_values.#{MemexProjectColumn::Reviewers.value_name}.actor_id": team_id } },
                      { term: { "field_values.#{MemexProjectColumn::Reviewers.value_name}.actor_type.keyword": "Team" } }
                    ]
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
            def value = field[params.value_name].find(val -> val.actor_id == params.id && val.actor_type == params.actor_type);
            if (value[params.update_key] == params.update_value) {
              ctx.op = 'noop';
            } else {
              value[params.update_key] = params.update_value;
            }
          """,
          params: {
            "field_type": MemexProjectColumn::Reviewers.data_type,
            "value_name": MemexProjectColumn::Reviewers.value_name,
            "update_key": "actor_slug",
            "update_value": T.must(model).name,
            "actor_type": "Team",
            "id": team_id
          }
        )
      end

      sig do override
        .params(es_client: ElasticsearchClient)
        .returns(Elastomer::Interfaces::Api::UpdateByQuery::Response)
      end
      def update(es_client)
        body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query: es_query, script: es_update)
        es_client.update_by_query(body)
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { returns(T.nilable(Integer)) }
      memoize private def team_id
        @message.dig(:team, :id)
      end
    end
  end
end
