# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class ProjectItemMove < Base
      include GitHub::Memoizer
      include GenericFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectItemMove\Z/,
        ]
      end

      sig { override.returns(Symbol) }
      def dependent_mysql_replication_cluster
        MemexProjectItem.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        item_id.present? && project_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        index.docs.exists?(id: item_id, type: document_type, routing: project_id)
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        model.present?
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        params = Elastomer::Interfaces::Api::Bulk::Request::Params.new(routing: project_id)
        es_client.bulk(params) do |bulk|

          # Apply all the column value updates represented by the message.
          column_value_updates.each do |update|
            field = MemexProjectColumn.find_by(id: update[:memex_project_column_id])&.to_field
            next unless field

            bulk.update(
              { script: field.elasticsearch_field_value_update_script(T.must(project_item)).to_hash },
              { _id: T.must(item_id), retry_on_conflict: Search::Memex::Client::RETRY_ON_CONFLICT },
            )
          end

          # Also apply a metadata update to capture changes to priority.
          bulk.update(
            { doc: T.must(model).elasticsearch_metadata.to_hash },
            { _id: T.must(item_id), retry_on_conflict: Search::Memex::Client::RETRY_ON_CONFLICT },
          )
        end
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        [T.must(project_id)]
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [model]
      end

      sig { returns(T.nilable(MemexProjectItem)) }
      memoize private def model
        MemexProjectItem.find_by(id: item_id)
      end

      sig { returns(T.nilable(Integer)) }
      private def item_id
        message.dig(:project_item, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        message.dig(:project, :id)
      end

      sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
      private def column_value_updates
        message.dig(:project_column_value_records)
      end
    end
  end
end
