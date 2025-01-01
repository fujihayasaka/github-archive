# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class AccountRename < Base
      extend T::Sig
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.AccountRename\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        User.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        model.present?
      end

      sig { returns(T.nilable(User)) }
      memoize private def model
        User.find_by(id: user_id)
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      private def es_query
        {
          "bool": {
            "filter": {
              "nested": {
                "path": "field_values",
                "query": {
                  "bool": {
                    "should": [
                      { "term": { "field_values.#{MemexProjectColumn::Assignees.value_name}.id": user_id } },
                      { "term": { "field_values.#{MemexProjectColumn::Reviewers.value_name}.actor_id": user_id } },
                      { "term": { "field_values.#{MemexProjectColumn::Repository.value_name}.owner_id": user_id } }
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
        user = T.must(model)
        Elastomer::Interfaces::Api::Request::Script.new(
          source: """
            for (def field_value : ctx._source.field_values) {
              // assignees conditional update
              if (field_value.field_slug == params.assignees_field_slug) {
                def assignee_value = field_value[params.assignees_value_key].find(val -> val[params.assignees_id_key] == params.id);
                if (assignee_value != null) {
                  assignee_value[params.assignees_update_key] = params.update_value;
                }
                continue;
              }

              // reviewers conditional update
              if (field_value.field_slug == params.reviewers_field_slug) {
                def reviewer_value = field_value[params.reviewers_value_key].find(val ->
                  val[params.reviewers_id_key] == params.id
                  && val[params.reviewers_type_key] == params.reviewers_type_value
                );
                if (reviewer_value != null) {
                  reviewer_value[params.reviewers_update_key] = params.update_value;
                }
                continue;
              }

              // repository conditional update
              if (field_value.field_slug == params.repository_field_slug) {
                def repository_value = field_value[params.repository_value_key];
                if (repository_value != null && repository_value[params.repository_id_key] == params.id) {
                  def repository_nwo = repository_value[params.repository_update_key];
                  repository_value[params.repository_update_key] = repository_nwo.replace(params.previous_login, params.update_value);
                }
              }
            }
          """,
          params: {
            # assignees update
            "assignees_field_slug": MemexProjectColumn::Assignees.data_type,
            "assignees_value_key": MemexProjectColumn::Assignees.value_name,
            "assignees_id_key": "id",
            "assignees_update_key": "login",

            # reviewers update
            "reviewers_field_slug": MemexProjectColumn::Reviewers.data_type,
            "reviewers_value_key": MemexProjectColumn::Reviewers.value_name,
            "reviewers_id_key": "actor_id",
            "reviewers_type_key": "actor_type",
            "reviewers_type_value": "User", # ReviewRequest model uses type as plain strings, no constants exist
            "reviewers_update_key": "actor_slug",

            # repository update
            "repository_field_slug": MemexProjectColumn::Repository.data_type,
            "repository_value_key": MemexProjectColumn::Repository.value_name,
            "repository_id_key": "owner_id",
            "repository_update_key": "full_name",

            "previous_login": previous_login,
            "update_value": user.display_login,
            "id": user.id
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
        # Note that, unlike some other processors, we fetch project ids from Elasticsearch rather than from MySQL.
        # Querying for all issues and draft issues with a particular assignee is an expensive operation that spans
        # multiple clusters. It is not yet apparent that fetching from Elasticsearch is an inferior approach. We'll
        # revisit this implementation if that changes.
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [model]
      end

      sig { returns(Integer) }
      memoize private def user_id
        @message.dig(:user, :id) || @message.dig(:account, :id)
      end

      sig { returns(String) }
      memoize private def previous_login
        @message.dig(:previous_login)
      end
    end
  end
end
