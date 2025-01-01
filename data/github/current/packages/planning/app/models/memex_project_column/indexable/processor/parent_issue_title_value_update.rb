# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class ParentIssueTitleValueUpdate < Base
      extend T::Sig
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
        return false if pull_request_id

        # confirm this message includes an issue title change
        message.dig(:previous_title) != message.dig(:current_title)
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        index.docs.count({ query: es_query }).dig("count") > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        related_project_items.length > 0 && model.present?
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: {
              nested: {
                path: "field_values",
                query: {
                  term: {
                    "field_values.parent_issue_value.id": issue_id
                  }
                }
              }
            }
          }
        }
      end

      sig do override
        .params(es_client: ElasticsearchClient)
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
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

      private

      sig { returns(Elastomer::Interfaces::Api::Request::Script) }
      def update_script
        Elastomer::Interfaces::Api::Request::Script.new(
          source: """
            def field = ctx._source.field_values.find(f -> f.field_type == params.field_type);
            if (field[params.value_name].title == params.updated_value) {
              ctx.op = 'noop';
            } else {
              field[params.value_name].title = params.updated_value;
            }
          """,
          params: {
            field_type: MemexProjectColumn::ParentIssue.data_type,
            value_name: MemexProjectColumn::ParentIssue.value_name,
            updated_value: updated_value
          }
        )
      end

      sig { returns(T::Array[MemexProjectItem]) }
      memoize def related_project_items
        return [] unless sub_issues = model&.sub_issues
        GitHub::PrefillAssociations.prefill_associations(sub_issues, :memex_project_items)
        sub_issues.flat_map { |sub_issue| sub_issue.memex_project_items }
      end

      sig { returns(String) }
      def updated_value
        T.must(self.model).title
      end

      sig { returns(T.nilable(Issue)) }
      memoize def model
        Issue.find_by(id: issue_id)
      end

      sig { returns(T.nilable(Integer)) }
      def issue_id
        message.dig(:issue, :id)
      end

      sig { returns(T.nilable(Integer)) }
      def pull_request_id
        message.dig(:pull_request, :id)
      end
    end
  end
end
