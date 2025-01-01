# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class BulkArchiveProjectItems < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.BulkArchiveProjectItems\Z/,
        ]
      end

      sig { override.returns(Symbol) }
      def dependent_mysql_replication_cluster
        MemexProjectItem.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        project_id.present? && item_ids.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        response = index.docs.multi_get(docs: item_ids.map { { _id: _1, _source: false, routing: project_id } })
        response["docs"].any? { _1["found"] }
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        updated_models.present?
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        es_client.bulk do |bulk|
          updated_models.each do |model|
            bulk.update(
              { doc: model.elasticsearch_metadata.to_hash },
              { _id: model.id, _routing: project_id, type: document_type, retry_on_conflict: 3 }
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
        MemexProjectItem.where(id: item_ids).to_a
      end

      sig { returns(T::Array[Integer]) }
      private def item_ids
        message.dig(:memex_project_item_ids)
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        message.dig(:memex_project, :id)
      end
    end
  end
end
