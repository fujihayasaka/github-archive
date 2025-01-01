# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class ProjectItemMove < Base
      extend T::Sig
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
        .params(es_client: ElasticsearchClient)
        .returns(Elastomer::Interfaces::Api::Update::Response)
      end
      def update(es_client)
        field = MemexProjectColumn.find_by(id: column_value_updates.first&.dig(:memex_project_column_id))&.to_field

        body = Elastomer::Interfaces::Api::Update::Request::Body.new(
          script: T.must(field).elasticsearch_field_value_and_priority_move_script(T.must(project_item))
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
