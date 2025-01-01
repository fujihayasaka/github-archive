# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class DraftIssueTitleUpdate < Base
      include GitHub::Memoizer
      include GenericFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.DraftIssueUpdateTitle\Z/,
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        DraftIssue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        project_id.present? && item_id.present? && draft_issue_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        response = index.docs.get(
          _source: false,
          id: item_id,
          routing: project_id,
          type: document_type
        )
        response["found"] == true
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        draft_issue.present?
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Update::Response)
      end
      def update(es_client)
        raise CanonicalDataMissingError unless value = updated_field_value&.to_hash

        script = Elastomer::Interfaces::Api::Request::Script.new(
          # To ensure we don't update unnecessarily, we noop when the content type has changed from a DraftIssue to an Issue
          # or if we find that the newest value exists already. Otherwise, we proceed by removing the existing metadata and
          # value and replace it with the new one. Note that we don't need to worry about replacing newer data with older data
          # because we're fetching the latest canonical data from the database.
          source: """
            def existing_field_value = ctx._source.field_values.find(field -> field.field_id == params.field_id);
            if (ctx._source.content.type != params.content_type || existing_field_value == params.value) {
              ctx.op = 'noop';
            } else {
              ctx._source.field_values.removeIf(field -> field.field_id == params.field_id);
              ctx._source.field_values.add(params.value);
            }
          """,
          params: {
            field_id: field.id,
            content_type: DraftIssue.name,
            value:,
          }
        )

        body = Elastomer::Interfaces::Api::Update::Request::Body.new(script:)
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
        [draft_issue, project_item]
      end

      sig { returns(T.nilable(MemexProjectItem)) }
      memoize private def project_item
        MemexProjectItem.find_by(id: item_id)
      end

      sig { returns(MemexProjectColumn::Field::Base) }
      memoize private def field
        # Note that title fields are auto-generated on project create, and can't be deleted, so we can be confident in T.must here.
        T.must(MemexProjectColumn.find_by(memex_project_id: project_id, name_slug: "title")&.to_field)
      end

      sig { returns(T.nilable(DraftIssue)) }
      memoize private def draft_issue
        DraftIssue.find_by(id: draft_issue_id)
      end

      sig { returns(T.nilable(Integer)) }
      private def draft_issue_id
        message.dig(:draft_issue, :id)
      end

      sig { returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::FieldValue)) }
      private def updated_field_value
        field.elasticsearch_field_value(T.must(project_item))
      end
    end
  end
end
