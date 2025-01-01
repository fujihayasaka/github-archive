# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class BulkAddProjectItems < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.BulkAddProjectItems\Z/,
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        MemexProjectItem.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        project_id.present? && item_ids.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        true
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        added_project_items.present? && project.present?
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        fields = project&.memex_project_columns&.map(&:to_field)&.compact || []
        project&.preload_elasticsearch_document_data(items: added_project_items, fields:)
        es_client.bulk do |bulk|
          added_project_items.each do |model|
            adapter = Elastomer::Adapters::MemexProjectItem.create(model)
            next unless (doc = adapter.to_hash)

            bulk.update(
              { doc: doc.except(:_id, :_type, :_routing), doc_as_upsert: true },
              { _id: model.id, _routing: project_id, type: document_type, retry_on_conflict: Search::Memex::Client::RETRY_ON_CONFLICT }
            )
          end
        end
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        [T.must(project_id)]
      end

      sig { override.returns(T::Array[MemexProjectItem]) }
      def updated_models
        added_project_items
      end

      sig { returns(T.nilable(MemexProject)) }
      memoize def project
        MemexProject.find_by(id: project_id)
      end

      sig { returns(T::Array[MemexProjectItem]) }
      memoize private def added_project_items
        MemexProjectItem.where(id: item_ids).to_a
      end

      sig { returns(T.nilable(T::Array[Integer])) }
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
