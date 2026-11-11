# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class ProcessProjectItem < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.DraftIssueUpdateAssignee\z/,
          /github\.memex\.v0\.ProjectItemCreate\Z/,
          /github\.memex\.v0\.DraftIssueConvertToIssue\Z/,
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
        true
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        return false unless adapter&.project_exists? && adapter&.content_exists?
        elasticsearch_document.present?
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Update::Response)
      end
      def update(es_client)
        doc = T.must(elasticsearch_document)
        body = Elastomer::Interfaces::Api::Update::Request::Body.new(
          doc: doc.except(:_id, :_type, :_routing),
          doc_as_upsert: true,
        )
        params = Elastomer::Interfaces::Api::Update::Request::Params.new(
          id: T.must(item_id),
          routing: project_id,
          refresh: update_refresh_strategy,
        )
        es_client.update(body, params)
      end

      # ProcessProjectItem historically forced an immediate refresh
      # (`Refresh::True`) rather than the client's `WaitFor` default, so a
      # project item is searchable on the very next request after it's
      # indexed. Override the base default to preserve that intent when the
      # skip-refresh flag is disabled.
      sig { override.returns(Elastomer::Interfaces::Api::Update::Request::Params::Refresh) }
      def update_refresh_strategy
        if skip_es_refresh?
          Elastomer::Interfaces::Api::Update::Request::Params::Refresh::False
        else
          Elastomer::Interfaces::Api::Update::Request::Params::Refresh::True
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

      sig { returns(T.nilable(Elastomer::Adapters::MemexProjectItem)) }
      memoize private def adapter
        return unless model
        Elastomer::Adapters::MemexProjectItem.create(model)
      end

      sig { returns(T.nilable(MemexProjectItem)) }
      memoize private def model
        MemexProjectItem.find_by(id: item_id)
      end

      sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      memoize private def elasticsearch_document
        adapter&.to_hash
      end

      sig { returns(T.nilable(Integer)) }
      private def item_id
        message.dig(:project_item, :id) || message.dig(:memex_project_item, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        message.dig(:project, :id) || message.dig(:memex_project, :id)
      end
    end
  end
end
