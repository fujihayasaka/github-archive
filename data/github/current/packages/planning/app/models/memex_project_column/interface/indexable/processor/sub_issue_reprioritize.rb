# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class SubIssueReprioritize < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.SubIssueReprioritize\Z/,
        ]
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        source_issue_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        target_issue_ids = sub_issue_relations.map(&:target_issue_id)
        return false if target_issue_ids.empty?

        index.docs.count({ query: es_query(target_issue_ids) }).dig("count") > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        !!(source_issue.present? && !sub_issue_relations.empty? && !related_project_items.empty?)
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        # Build a mapping of target_issue_id => stringified priority from SubIssue relations
        priority_map = sub_issue_relations.index_by(&:target_issue_id).transform_values(&:stringified_priority).compact

        es_client.bulk do |bulk|
          related_project_items.each do |project_item|
            content_id = project_item.issue_id
            next unless content_id

            # Get the priority for this specific issue from our mapping
            priority = priority_map[content_id]
            next unless priority

            bulk.update(
              { doc: { content: { sub_issue_priority: priority } } },
              { _id: project_item.id, routing: project_item.memex_project_id, retry_on_conflict: 3 }
            )
          end
        end
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        related_project_items.pluck(:memex_project_id).uniq
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [source_issue, *target_issues, *related_project_items].compact
      end

      private

      sig { returns(T.nilable(Issue)) }
      memoize def source_issue
        return nil unless source_issue_id
        Issue.find_by(id: source_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { returns(T::Array[Issue]) }
      memoize def target_issues
        target_issue_ids = sub_issue_relations.map(&:target_issue_id)
        return [] if target_issue_ids.empty?

        Issue.where(id: target_issue_ids).to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      # Get all sub-issue relations for the source (parent) issue
      sig { returns(T::Array[SubIssue]) }
      memoize def sub_issue_relations
        return [] unless source_issue_id

        SubIssue.where(source_issue_id: source_issue_id).to_a
      end

      # Get all project items that match any of the target issue ids
      sig { returns(T::Array[MemexProjectItem]) }
      memoize def related_project_items
        target_issue_ids = sub_issue_relations.map(&:target_issue_id)
        return [] if target_issue_ids.empty?

        MemexProjectItem.where(issue_id: target_issue_ids).to_a
      end

      # Query for all project items that match any of the target issue ids
      sig { params(target_issue_ids: T::Array[Integer]).returns(T::Hash[T::untyped, T::untyped]) }
      def es_query(target_issue_ids)
        {
          bool: {
            filter: [
              { terms: { "content.id": target_issue_ids } },
              { term: { "content.type": "Issue" } },
            ],
          }
        }
      end

      # "Source" refers to the parent issue
      sig { returns(T.nilable(Integer)) }
      def source_issue_id
        @message.dig(:source_issue, :id)
      end
    end
  end
end
