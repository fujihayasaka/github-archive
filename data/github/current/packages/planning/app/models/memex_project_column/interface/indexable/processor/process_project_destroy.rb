# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class ProcessProjectDestroy < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.ProjectDestroy\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        # Since we're deleting we don't need to reference any canonical data
        nil
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        project_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        # We're just going to post a delete request that will noop if no matching documents are found so there is no
        # reason to add an extra check here.
        true
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        # The canonical data conditions that suggest proceeding with the delete are when there is no canonical data
        # (because it has been deleted). We trust there is no way for a project destroy event to occur without
        # the project having actually been hard deleted.
        true
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::DeleteByQuery::Response)
      end
      def update(es_client)
        query = { bool: { filter: { term: { memex_project_id: project_id } } } }
        es_client.delete_by_query(
          Elastomer::Interfaces::Api::DeleteByQuery::Request::Body.new(query:),
          Elastomer::Interfaces::Api::DeleteByQuery::Request::Params.new(routing: project_id)
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
      private def project_id
        message.dig(:memex_project, :id)
      end
    end
  end
end
