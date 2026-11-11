# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class ProjectItemMetadataUpdate < Base
      include GitHub::Memoizer

      FEATURE_FLAG_SKIP_REFRESH = :memex_project_item_metadata_update_skip_refresh

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.ProjectItemMetadataUpdate\Z/,
        ]
      end

      sig { override.returns(StreamProcessorKey) }
      def self.stream_processor_key
        StreamProcessorKey::LowPriority
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
        .returns(T.any(Elastomer::Interfaces::Api::Update::Response, Elastomer::Interfaces::Api::Bulk::Response::Body))
      end
      def update(es_client)
        item = T.must(model)

        field = MemexProjectColumn.find_by(
          memex_project_id: item.memex_project_id,
          data_type: MemexProjectColumn::Field::Updated.data_type,
        )&.to_field

        unless field
          return es_client.update(
            Elastomer::Interfaces::Api::Update::Request::Body.new(doc: item.elasticsearch_metadata.to_hash),
            Elastomer::Interfaces::Api::Update::Request::Params.new(id: T.must(item_id), routing: project_id, refresh: refresh_param),
          )
        end

        bulk_refresh = Elastomer::Interfaces::Api::Bulk::Request::Params::Refresh.deserialize(refresh_param.serialize)

        es_client.bulk(Elastomer::Interfaces::Api::Bulk::Request::Params.new(refresh: bulk_refresh)) do |bulk|
          bulk.update(
            { doc: item.elasticsearch_metadata.to_hash },
            { _id: T.must(item_id), _routing: project_id, retry_on_conflict: Search::Memex::Client::RETRY_ON_CONFLICT }
          )
          bulk.update(
            { script: field.elasticsearch_field_value_update_script(item).to_hash },
            { _id: T.must(item_id), _routing: project_id, retry_on_conflict: Search::Memex::Client::RETRY_ON_CONFLICT }
          )
        end
      end

      sig { override.returns(T::Hash[String, String]) }
      def update_extra_tags
        { "refresh" => refresh_param.serialize }
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        [T.must(project_id)]
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [model]
      end

      sig { override.returns(T::Boolean) }
      def broadcast_result?
        metadata_attributes = JSON.parse(message.dig(:previous_values)).keys.map(&:to_sym)
        has_changes_besides_updated_at = (metadata_attributes - %i[updated_at]).any?

        has_changes_besides_updated_at
      rescue JSON::ParserError
        # If we can't say for sure what changed, then broadcast the result by default.
        true
      end

      sig { returns(T.nilable(MemexProjectItem)) }
      memoize private def model
        MemexProjectItem.find_by(id: item_id)
      end

      sig { returns(T.nilable(Integer)) }
      private def item_id
        message.dig(:memex_project_item, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        message.dig(:memex_project, :id)
      end

      sig { returns(Elastomer::Interfaces::Api::Update::Request::Params::Refresh) }
      memoize private def refresh_param
        if !broadcast_result? && FeatureFlag.vexi.enabled?(FEATURE_FLAG_SKIP_REFRESH, default: false)
          Elastomer::Interfaces::Api::Update::Request::Params::Refresh::False
        else
          Elastomer::Interfaces::Api::Update::Request::Params::Refresh::WaitFor
        end
      end
    end
  end
end
