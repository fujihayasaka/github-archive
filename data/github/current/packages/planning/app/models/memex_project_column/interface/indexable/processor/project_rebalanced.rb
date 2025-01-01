# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class ProjectRebalanced < Base
      include GitHub::Memoizer

      BATCH_SIZE = 1000

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.prioritizable\.v0\.PrioritizableContextRebalanced\Z/
        ]
      end

      sig { override.returns(Symbol) }
      def dependent_mysql_replication_cluster
        MemexProjectItem.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        !!(project_id.present? && context_type == ::MemexProject.name)
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count_all(es_query) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        memex_project_items.size > 0
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(T::Array[Elastomer::Interfaces::Api::Bulk::Response::Body])
      end
      def update(es_client)
        bulk_update_responses = []
        items = memex_project_items
        last_processed_id = T.let(0, Integer)

        loop do
          bulk_update_responses << es_client.bulk(bulk_options) do |bulk|
            items.each do |item|
              bulk.update(
                { doc: { virtual_priority: item.stringified_virtual_priority } },
                { _id: item.id, _routing: project_id, _type: document_type }.compact
              )
              last_processed_id = item.id
            end
          end

          # load the next batch of items
          items = memex_project_items(offset_id: last_processed_id)
          break unless items.size > 0
        end

        bulk_update_responses
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        [T.must(project_id)]
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        []
      end

      sig { returns(Elastomer::Interfaces::Api::Bulk::Request::Params) }
      memoize private def bulk_options
        Elastomer::Interfaces::Api::Bulk::Request::Params.new(timeout: "5m")
      end

      sig { returns(T::Hash[String, T.untyped]) }
      memoize private def es_query
        {
          "query": {
            "bool": {
              "filter": [
                { "term": { "_routing": project_id } }
              ]
            }
          }
        }
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        message.dig(:context_id)
      end

      sig { returns(T.nilable(String)) }
      private def context_type
        message.dig(:context_type)
      end

      sig { returns(T.nilable(String)) }
      private def document_type
        return if @index.index_running_version_8_plus?
        Elastomer::Adapters::MemexProjectItem.document_type
      end

      sig { params(offset_id: Integer).returns(T::Array[::MemexProjectItem]) }
      private def memex_project_items(offset_id: 0)
        ::MemexProjectItem
          .select(:id, :priority_numerator, :priority_denominator)
          .order(:id)
          .where(memex_project_id: project_id)
          .where("id > ?", offset_id)
          .limit(BATCH_SIZE)
          .to_a
      end
    end
  end
end
