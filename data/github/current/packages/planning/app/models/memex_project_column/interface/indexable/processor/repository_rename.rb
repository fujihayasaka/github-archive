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
        @index.count_all({ query: es_query }) > 0
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
          def repository_field = ctx._source.field_values.find(f -> f.field_slug == params.field_slug);

          if (repository_field != null) {

            def repository_value = repository_field[params.repository_value_key];

            if (repository_value != null) {
              repository_value.full_name = params.update_value;
            }

          }
          """,
          params: {
            field_slug: MemexProjectColumn::Field::Repository.data_type,
            repository_value_key: MemexProjectColumn::Field::Repository.value_name,
            update_value: repository.full_name
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

      sig { returns(T.nilable(Repository)) }
      memoize private def model
        if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
          T.cast(Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
        else
          Repository.find_by(id: repository_id)
        end
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
