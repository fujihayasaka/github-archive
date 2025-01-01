# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IssueDependencyUpdates < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.BlockedByAdd\Z/,
          /github\.v1\.BlockedByRemove\Z/,
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        # Serializer will serialize the issue IDs as integers, so we can check for presence and non-zero values.
        source_issue_missing = source_issue_id.blank? || source_issue_id == 0
        target_issue_missing = target_issue_id.blank? || target_issue_id == 0
        # Valid if either source or target issue is present.
        # Source or target may be missing if an issue was deleted, in which case we'll still update the other issue's dependencies.
        return false if source_issue_missing && target_issue_missing
        # Prevent self-referencing dependencies
        return false if source_issue_id == target_issue_id
        true
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        index.docs.count({ query: es_query }).dig("count") > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        related_project_items.length > 0
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        # Return all documents that have a "content.id" matching the source_issue_id or target_issue_id,
        # and that have "content.type" equal to "Issue".
        {
          bool: {
            should: [
              { term: { "content.id": source_issue_id } },
              { term: { "content.id": target_issue_id } }
            ],
            filter: { term: { "content.type": "Issue" } },
            minimum_should_match: 1
          }
        }
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        blocked_by_script = update_blocked_by_script.to_hash
        blocking_script = update_blocking_script.to_hash

        es_client.bulk do |bulk|
          project_items_to_update_blocked_by.each do |item|
            bulk.update(
              { script: blocked_by_script },
              { id: item.id, routing: item.memex_project_id, type: document_type, retry_on_conflict: 3 }
            )
          end
          project_items_to_update_blocking.each do |item|
            bulk.update(
              { script: blocking_script },
              { id: item.id, routing: item.memex_project_id, type: document_type, retry_on_conflict: 3 }
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
        [model, target_model, *related_project_items].compact
      end

      private

      # Script for only updating the blocked_by field in the MemexProjectItem documents
      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def update_blocked_by_script
        Elastomer::Interfaces::Api::Request::Script.new(
          source: """
          ctx._source.content.blocked_by = params.new_blocked_by;
          """,
          params: {
            new_blocked_by: new_blocked_by,
          }
        )
      end

      # Script for only updating the blocking field in the MemexProjectItem documents
      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def update_blocking_script
        Elastomer::Interfaces::Api::Request::Script.new(
          source: """
          ctx._source.content.blocking = params.new_blocking;
          """,
          params: {
            new_blocking: new_blocking,
          }
        )
      end

      sig { returns(T::Array[MemexProjectItem]) }
      memoize def related_project_items
        project_items_to_update_blocked_by | project_items_to_update_blocking
      end

      sig { returns(T::Array[MemexProjectItem]) }
      memoize def project_items_to_update_blocked_by
        return [] unless model = self.model
        MemexProjectItem.where(issue_id: model.id).to_a
      end

      sig { returns(T::Array[MemexProjectItem]) }
      memoize def project_items_to_update_blocking
        return [] unless target_model = self.target_model
        MemexProjectItem.where(issue_id: target_model.id).to_a
      end

      sig { returns(T.nilable(T::Array[Elastomer::Interfaces::Document::MemexProjectItem::DependencyIssue])) }
      memoize def new_blocked_by
        return unless model = self.model
        return unless repository = self.repository
        model.blocked_by.map do |blocking_issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          Elastomer::Interfaces::Document::MemexProjectItem::DependencyIssue.new(
            id: blocking_issue.id,
            nwo_reference: blocking_issue.name_with_display_owner_reference,
            owner_id: repository.owner_id,
          )
        end
      end

      sig { returns(T.nilable(T::Array[Elastomer::Interfaces::Document::MemexProjectItem::DependencyIssue])) }
      memoize def new_blocking
        return unless target_model = self.target_model
        return unless target_repository = self.target_repository
        target_model.blocking.map do |blocked_issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          Elastomer::Interfaces::Document::MemexProjectItem::DependencyIssue.new(
            id: blocked_issue.id,
            nwo_reference: blocked_issue.name_with_display_owner_reference,
            owner_id: target_repository.owner_id,
          )
        end
      end

      sig { returns(T.nilable(Issue)) }
      memoize def model
        return nil unless source_issue_id = self.source_issue_id
        Issue.find_by(id: source_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { returns(T.nilable(Issue)) }
      memoize def target_model
        return nil unless target_issue_id = self.target_issue_id
        Issue.find_by(id: target_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { returns(T.nilable(Repository)) }
      memoize def repository
        return nil unless model = self.model
        model.repository
      end

      sig { returns(T.nilable(Repository)) }
      memoize def target_repository
        return nil unless target_model = self.target_model
        target_model.repository
      end

      sig { returns(T.nilable(Integer)) }
      def source_issue_id
        message.dig(:source_issue, :id)
      end

      sig { returns(T.nilable(Integer)) }
      def target_issue_id
        message.dig(:target_issue, :id)
      end
    end
  end
end
