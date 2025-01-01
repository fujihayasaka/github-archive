# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class ProjectItemMetadataUpdate < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.ProjectItemMetadataUpdate\Z/,
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
        .returns(Elastomer::Interfaces::Api::Update::Response)
      end
      def update(es_client)
        body = Elastomer::Interfaces::Api::Update::Request::Body.new(
          doc: T.must(model).elasticsearch_metadata.to_hash,
        )
        params = Elastomer::Interfaces::Api::Update::Request::Params.new(
          id: T.must(item_id),
          routing: project_id,
        )
        es_client.update(body, params)
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
    end
  end
end
