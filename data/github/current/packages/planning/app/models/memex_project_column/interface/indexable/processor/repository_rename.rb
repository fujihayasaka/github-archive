# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class RepositoryRename < Base
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.RepositoryRename\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Repository.cluster_name
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

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [model]
      end

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def es_update
        repository = T.must(model)
        Elastomer::Interfaces::Api::Request::Script.new(
          source: """
          def repository_field = ctx._source.field_values.find(f -> f.field_type == params.field_type);

          if (repository_field != null) {

            def repository_value = repository_field[params.repository_value_key];

            if (repository_value != null) {
              repository_value.full_name = params.full_name;
              repository_value.name_with_display_owner = params.name_with_display_owner;
            }

          }
          """,
          params: {
            field_type: MemexProjectColumn::Field::Repository.data_type,
            repository_value_key: MemexProjectColumn::Field::Repository.value_name,
            full_name: repository.full_name,
            name_with_display_owner: repository.name_with_display_owner,
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

      sig { returns(T.nilable(Repository)) }
      memoize private def model
        T.cast(Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      private def es_query
        {
          bool: {
            filter: {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.#{MemexProjectColumn::Field::Repository.value_name}.id": repository_id
                  }
                }
              }
            }
          }
        }
      end

      sig { returns(Integer) }
      memoize private def repository_id
        @message.dig(:repository, :id)
      end
    end
  end
end
