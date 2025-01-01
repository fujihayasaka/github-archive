# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IssueTransferUpdates < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.IssueTransferred\Z/
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
        model.present?
      end

      sig { returns(T.nilable(Issue)) }
      memoize private def model
        Issue.includes(:labels, :milestone).find_by(id: new_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: [
              { term: { "content.id": old_issue_id, } },
              { term: { "content.type": "Issue" } }
            ]
          }
        }
      end

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def es_update
        issue = T.must(model)
        Elastomer::Interfaces::Api::Request::Script.new({
          source: """
            def content = ctx._source.content;
            if (content.repository_id != params.new_repository_id) {
              content.id = params.new_issue_id;
              content.number = params.new_issue_number;
              content.repository_id = params.new_repository_id;

              for (def field_value : ctx._source.field_values) {
                if (field_value.field_slug == params.repository_field_slug) {
                  if (field_value[params.repository_value_key].id != params.repository_value.id) {
                    field_value[params.repository_value_key] = params.repository_value;
                  }
                  continue;
                }

                if (field_value.field_slug == params.labels_field_slug) {
                  field_value[params.labels_field_key] = params.labels_value;
                  continue;
                }

                if (field_value.field_slug == params.milestone_field_slug) {
                  field_value[params.milestone_value_key] = params.milestone_value;
                }
              }
            } else {
              ctx.op = 'noop';
            }
          """,
          params: {
            new_issue_id: issue.id,
            new_issue_number: issue.number,
            new_repository_id: new_repository_id,
            repository_field_slug: MemexProjectColumn::Field::Repository.data_type,
            repository_value_key: MemexProjectColumn::Field::Repository.value_name,
            repository_value: repository_value,
            labels_field_slug: MemexProjectColumn::Field::Labels.data_type,
            labels_field_key: MemexProjectColumn::Field::Labels.value_name,
            labels_value: labels_value,
            milestone_field_slug: MemexProjectColumn::Field::Milestone.data_type,
            milestone_value_key: MemexProjectColumn::Field::Milestone.value_name,
            milestone_value: milestone_value,
          }
        })
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::UpdateByQuery::Response)
      end
      def update(es_client)
        body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query: es_query, script: es_update)
        es_client.update_by_query(body)
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        model&.memex_project_items&.map(&:memex_project_id)&.uniq&.compact || []
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [model, *model&.memex_project_items]
      end

      sig { returns(Elastomer::Interfaces::Document::MemexProjectItem::RepositoryValue) }
      memoize private def repository_value
        repository = T.must(new_repository)
        Elastomer::Interfaces::Document::Repository.new({
          id: repository.id,
          full_name: repository.full_name,
          owner_id: repository.owner_id,
          owner_type: repository.owner&.type,
        })
      end

      sig { returns(Elastomer::Interfaces::Document::MemexProjectItem::MilestoneValue) }
      memoize private def milestone_value
        issue = T.must(model)
        return nil unless issue.milestone != nil

        milestone = T.must(issue.milestone)
        Elastomer::Interfaces::Document::Milestone.new({
          id: milestone.id,
          title: milestone.title,
          repository_id: new_repository_id
        })
      end

      sig { returns(Elastomer::Interfaces::Document::MemexProjectItem::LabelsValue) }
      memoize private def labels_value
        labels = T.must(model&.labels)
        labels.map do |label|
          Elastomer::Interfaces::Document::Label.new({
            id: label.id,
            name: label.name,
            repository_id: new_repository_id
          })
        end
      end

      sig { returns(T.nilable(Repository)) }
      memoize private def new_repository
        if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
          T.cast(Repositories.domain.by_id(new_repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
        else
          Repository.find_by(id: new_repository_id)
        end
      end

      sig { returns(T.nilable(Integer)) }
      memoize private def old_issue_id
        @message.dig(:old_issue, :id)
      end

      sig { returns(T.nilable(Integer)) }
      memoize private def new_issue_id
        @message.dig(:new_issue, :id)
      end

      sig { returns(Integer) }
      memoize private def new_repository_id
        @message.dig(:new_repository, :id)
      end
    end
  end
end
