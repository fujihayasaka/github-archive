# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class ProcessProjectItemDelete < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.ProjectItemDestroy\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        # Since we're deleting we don't need to reference any canonical data
        nil
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        item_id.present? && project_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        # We're just going to post a delete request that will noop if no matching document is found so there is no
        # reason to add an extra check here.
        true
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        # The canonical data conditions that suggest proceeding with the delete are when there is no canonical data
        # (because it has been deleted). We trust there is no way for a project item delete event to occur without
        # the item actually being deleted.
        true
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Delete::Response)
      end
      def update(es_client)
        es_client.delete(
          Elastomer::Interfaces::Api::Delete::Request::Params.new(
            id: T.must(item_id),
            routing: project_id,
          )
        )
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        [T.must(project_id)]
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        []
      end

      sig { returns(T.nilable(Integer)) }
      private def item_id
        message.dig(:memex_project_item, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        return message.dig(:memex_project, :id) if GitHub.flipper[:memex_bulk_destroy_processing_only].enabled?

        message.dig(:memex_project, :id) || message.dig(:memex_project_item, :memex_project_id)
      end
    end
  end
end
