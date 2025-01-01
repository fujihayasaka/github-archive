# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class BulkDeleteProjectItems < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.ProjectItemDestroy\Z/,
          /github\.memex\.v0\.BulkDeleteProjectItems\Z/,
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        MemexProject.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        !!(project_id.present? && item_ids.present?)
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        # The eventual bulk delete request will noop on missing documents, so it is more efficient
        # to just issue it without querying Elasticsearch first.
        true
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        # We require that the parent project is still present in the database. Otherwise, the event that we're
        # consuming was the result of a project deletion, and it should be handled by `ProcessProjectDestroy` rather
        # than this processor.
        project.present?
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        es_client.bulk do |bulk|
          T.must(item_ids).each do |id|
            bulk.delete(
              {
                _id: id,
                _routing: project_id,
                type: document_type
              }.compact
            )
          end
        end
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        [T.must(project_id)]
      end

      sig { override.returns(T::Array[MemexProjectItem]) }
      memoize def updated_models
        # The models that might otherwise need to be refetched were just deleted.
        []
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      private def item_ids
        if single_item_id = message.dig(:memex_project_item, :id)
          # Extract item IDs from a `github.memex.v0.ProjectItemDestroy` payload
          [single_item_id]
        else
          # Extract item IDs from a `github.memex.v0.BulkDeleteProjectItems` payload
          message.dig(:memex_project_item_ids)
        end
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        message.dig(:memex_project, :id)
      end

      sig { returns(T.nilable(MemexProject)) }
      private def project
        MemexProject.find_by(id: project_id)
      end
    end
  end
end
