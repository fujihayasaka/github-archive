# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class RepositoryTransfer < Base
      include GitHub::Memoizer
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.repositories\.v1\.Transferred\Z/
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

      sig { returns(T.nilable(Repository)) }
      memoize private def model
        Repository.includes(:owner).find_by(id: repository_id)
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

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def es_update
        repository = T.must(model)
        member_ids = []
        update_script = ""

        if can_assignees_be_changed?
          update_script = """
            def has_update = false;
            for (def field_value : ctx._source.field_values) {
              if (field_value.field_slug == params.repository_field_slug) {
                if (field_value[params.repository_value_key] != params.updated_value) {
                  field_value[params.repository_value_key] = params.updated_value;
                  has_update = true;
                }
              }

              if (field_value.field_slug == params.assignees_field_slug) {
                if (field_value[params.assignees_value_key].removeIf(assignee -> !params.member_ids.contains(assignee.id))) {
                  has_update = true;
                  if (field_value[params.assignees_value_key].isEmpty()) {
                    ctx._source.field_values.removeIf(f -> f == field_value)
                  }
                }
              }
            }

            if (!has_update) {
              ctx.op = 'noop';
            }
          """
          member_ids = transferred_repo_member_ids # only query members if necessary
        else
          update_script = """
            def field = ctx._source.field_values.find(f -> f.field_slug == params.repository_field_slug);
            if (field == null || field[params.repository_value_key] == params.updated_value) {
              ctx.op = 'noop';
            } else {
              field[params.repository_value_key] = params.updated_value;
            }
          """
        end

        Elastomer::Interfaces::Api::Request::Script.new(
          source: update_script,
          params: {
            "repository_field_slug": MemexProjectColumn::Field::Repository.data_type,
            "repository_value_key": MemexProjectColumn::Field::Repository.value_name,
            "assignees_field_slug": MemexProjectColumn::Field::Assignees.data_type,
            "assignees_value_key": MemexProjectColumn::Field::Assignees.value_name,
            "updated_value": updated_value,
            "member_ids": member_ids
          },
        )
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::UpdateByQuery::Response)
      end
      def update(es_client)
        request = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query: es_query, script: es_update)
        es_client.update_by_query(request)
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [model]
      end

      sig { returns(Integer) }
      memoize private def repository_id
        @message.dig(:repository_id)
      end

      sig { returns(String) }
      memoize private def previous_owner_type
        @message.dig(:previous_owner, :type).to_s.capitalize
      end

      ## Private repository that belong to an org can have their assignees changed
      ## because teams are removed from the repository when the owner changes
      sig { returns(T::Boolean) }
      private def can_assignees_be_changed?
        repository = T.must(model)

        !repository.public? && previous_owner_type == "Organization"
      end

      ## Retrieves all member ids of the transferred repository to update
      ## assignees of Issues and PRs
      sig { returns(T::Array[Integer]) }
      memoize private def transferred_repo_member_ids
        repository = T.must(model)
        repository.all_member_and_owner_ids
      end

      sig { returns(Elastomer::Interfaces::Document::MemexProjectItem::RepositoryValue) }
      private def updated_value
        repository = T.must(model)
        owner = T.must(repository.owner)
        Elastomer::Interfaces::Document::Repository.new({
          id: repository.id,
          owner_id: owner.id,
          owner_type: owner.type,
          full_name: repository.full_name
        })
      end
    end
  end
end
