# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    # Updates the `in_project` boolean on the parent_issue field value for sub-issues
    # when a parent issue is added to or removed from a project.
    #
    # When a parent issue is added to a project (`ProjectItemCreate`), any sub-issues
    # of that parent that are also in the same project should have their `in_project`
    # field set to `true`.
    #
    # When a parent issue is removed from a project (`ProjectItemDestroy`), those
    # sub-issues should have their `in_project` field set to `false`.
    class ParentIssueProjectChange < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.ProjectItemCreate\Z/,
          /github\.memex\.v0\.ProjectItemDestroy\Z/,
        ]
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        issue_id.present? && project_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        return false if sub_issue_ids.empty?

        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        !sub_issue_ids.empty? && !related_project_items.empty?
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        MemexProjectItem.cluster_name
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        raise CanonicalDataMissingError unless related_project_items.present?

        script = update_script.to_hash

        es_client.bulk do |bulk|
          related_project_items.each do |item|
            bulk.update(
              { script: },
              { _id: item.id, routing: item.memex_project_id, retry_on_conflict: 3 }
            )
          end
        end
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        [T.must(project_id)]
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        related_project_items
      end

      private

      # The issue ID of the content that was added to or removed from the project.
      # This is the potential parent issue.
      sig { returns(T.nilable(Integer)) }
      def issue_id
        @message.dig(:memex_project_item, :issue, :id)
      end

      sig { returns(T.nilable(Integer)) }
      def project_id
        @message.dig(:memex_project, :id)
      end

      sig { returns(T::Boolean) }
      def create_event?
        @message.topic.match?(/ProjectItemCreate\Z/)
      end

      # Find the IDs of sub-issues (children) of the added/removed parent issue.
      sig { returns(T::Array[Integer]) }
      memoize def sub_issue_ids
        return [] unless issue_id

        SubIssue.where(source_issue_id: issue_id).limit(SubIssue::MAXIMUM_BREADTH).pluck(:target_issue_id)
      end

      # Find project items in the same project for sub-issues of the parent.
      sig { returns(T::Array[MemexProjectItem]) }
      memoize def related_project_items
        return [] if sub_issue_ids.empty?

        MemexProjectItem
          .where(
            memex_project_id: project_id,
            issue_id: sub_issue_ids,
          )
          .select(:id, :memex_project_id)
          .to_a
      end

      # Elasticsearch query to find documents for sub-issues in the affected project.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      memoize def es_query
        {
          bool: {
            filter: [
              { terms: { "content.id": sub_issue_ids } },
              { term: { "content.type": "Issue" } },
              { term: { "_routing": project_id } },
            ]
          }
        }
      end

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def update_script
        Elastomer::Interfaces::Api::Request::Script.new(
          source: """
            def field = ctx._source.field_values.find(f -> f.field_type == params.field_type);
            if (field != null && field[params.value_name] != null) {
              if (field[params.value_name].in_project == params.in_project) {
                ctx.op = 'noop';
              } else {
                field[params.value_name].in_project = params.in_project;
              }
            } else {
              ctx.op = 'noop';
            }
          """,
          params: {
            field_type: MemexProjectColumn::Field::ParentIssue.data_type,
            value_name: MemexProjectColumn::Field::ParentIssue.value_name,
            in_project: create_event?,
          }
        )
      end
    end
  end
end
