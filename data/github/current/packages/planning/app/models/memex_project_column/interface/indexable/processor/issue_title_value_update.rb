# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IssueTitleValueUpdate < Base
      include GitHub::Memoizer

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v2\.IssueUpdate\Z/,
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        return false if issue_id.blank?

        # confirm this message includes an issue title change
        message.dig(:previous_title) != message.dig(:current_title)
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        index.docs.count({ query: es_query }).dig("count") > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        model.present?
      end

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def es_query
        {
          bool: {
            filter: [
              { term: { "content.type": content_type } },
              { term: { "content.id": content_id } }
            ]
          }
        }
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        raise CanonicalDataMissingError unless related_project_items.present?
        script = update_script.to_hash

        es_client.bulk do |bulk|
          related_project_items.each do |item|
            bulk.update(
              { script: },
              { id: item.id, routing: item.memex_project_id, type: document_type, retry_on_conflict: 3 }
            )
          end
        end
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        related_project_items.pluck(:memex_project_id)&.uniq || []
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [model, *related_project_items]
      end

      private

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def update_script
        Elastomer::Interfaces::Api::Request::Script.new(
          # To ensure we don't update unnecessarily, we noop if we find that the newest value exists already. Since
          # we are querying across all projects, we use the unique `value_name` to identify the field we want to update
          # rather than the column id (which is different for every project).
          source: """
            def target_field = ctx._source.field_values.find(field -> field.containsKey(params.value_name));
            if (target_field[params.value_name] == params.updated_value) {
              ctx.op = 'noop';
            } else {
              target_field[params.value_name] = params.updated_value;
            }
          """,
          params: {
            value_name: MemexProjectColumn::Field::Title.value_name,
            updated_value: updated_value
          }
        )
      end

      sig { returns(T::Array[MemexProjectItem]) }
      memoize def related_project_items
        model&.memex_project_items.to_a
      end

      sig { returns(Elastomer::Interfaces::Document::MemexProjectItem::TitleValue) }
      def updated_value
        T.must(model).title
      end

      sig { returns(T.nilable(T.any(Issue, PullRequest))) }
      memoize def model
        pull_request_id ? PullRequest.find_by(id: pull_request_id) : Issue.find_by(id: issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      sig { returns(T.nilable(Integer)) }
      def issue_id
        message.dig(:issue, :id)
      end

      sig { returns(T.nilable(Integer)) }
      def pull_request_id
        message.dig(:pull_request, :id)
      end

      sig { returns(T.nilable(Integer)) }
      def content_id
        pull_request_id || issue_id
      end

      sig { returns(String) }
      def content_type
        pull_request_id ? "PullRequest" : "Issue"
      end
    end
  end
end
