# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    # Updates the embedded `content` object in Elasticsearch when an issue or pull request changes state
    # (e.g. closed, reopened, merged, converted to draft). This keeps fields like `content.state` in sync
    # with the canonical source in MySQL.
    #
    # For the subset of events that also change `closed_at` (close, reopen, merge), this processor
    # additionally updates the `Field::Closed` field value in Elasticsearch. Handling both updates
    # in a single processor avoids running two processors sequentially for the same topic, which
    # would otherwise risk exceeding the Hydro consumer session timeout.
    class ContentStateChange < Base
      include GitHub::Memoizer
      include ContentHelpers

      # The subset of topics that change the closed timestamp and therefore require a Field::Closed update
      CLOSED_TIMESTAMP_TOPICS = T.let(
        [
          /github\.v1\.IssueClose\Z/,
          /github\.v1\.IssueReopen\Z/,
          /github\.v1\.PullRequestClose\Z/,
          /github\.v1\.PullRequestReopen\Z/,
          /github\.v1\.PullRequestMerge\Z/,
        ],
        T::Array[Regexp]
      )

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.IssueClose\Z/,
          /github\.v1\.IssueReopen\Z/,
          /github\.v1\.IssueConvertedToDiscussion\Z/,
          /github\.v1\.PullRequestClose\Z/,
          /github\.v1\.PullRequestReopen\Z/,
          /github\.v1\.PullRequestMerge\Z/,
          /github\.v1\.PullRequestConvertToDraft\Z/,
          /github\.v1\.PullRequestReadyForReview\Z/,
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        case content_type
        when "Issue"
          Issue.cluster_name
        when "PullRequest"
          PullRequest.cluster_name
        else
          raise NotImplementedError
        end
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        if any_match_helper_enabled?
          @es_client.any_match?(es_query)
        else
          @index.count_all({ query: es_query }) > 0
        end
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        content.present?
      end

      sig { override.returns(T.nilable(T.any(Issue, PullRequest))) }
      memoize public def content
        case content_type
        when "Issue"
          Issue.find_by(repository_id: repository_id, id: content_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        when "PullRequest"
          PullRequest.find_by(repository_id: repository_id, id: content_id)
        else
          raise NotImplementedError
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      memoize private def es_query
        {
          bool: {
            filter: [
              { term: { "content.repository_id": @message.dig(:repository, :id) } },
              { term: { "content.id": content_id } },
              { term: { "content.type": content_type } },
            ]
          }
        }
      end

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(T::Array[Elastomer::Interfaces::Api::Bulk::Response::Body])
      end
      def update(es_client)
        raise CanonicalDataMissingError unless project_items_for_content.present? && content_elasticsearch_document.present?

        if closed_timestamp_topic?
          # Field::Closed reads item.issue_closed_at, a denormalized column updated by
          # HydroCopyIssueDataToMemexProjectItemJob. Since that job races with this processor,
          # we stamp the value from the canonical model onto items in-memory before indexing.
          fresh_closed_at = content&.closed_at
          project_items_for_content.each { |item| item.issue_closed_at = fresh_closed_at }
          closed_fields_by_item_id = fields_by_item_id_for_content(field_class: MemexProjectColumn::Field::Closed)

          result = es_client.bulk(bulk_params) do |bulk|
            project_items_for_content.each do |item|
              bulk.update(
                { doc: { content: content_elasticsearch_document } },
                { _id: item.id, _routing: item.memex_project_id, retry_on_conflict: 3 }
              )

              if field = closed_fields_by_item_id[item.id]
                bulk.update(
                  { script: field.elasticsearch_field_value_update_script(item).to_hash },
                  { _id: item.id, _routing: item.memex_project_id, retry_on_conflict: 3 }
                )
              end
            end
          end

          return [result]
        end

        result = es_client.bulk(bulk_params) do |bulk|
          project_items_for_content.each do |item|
            bulk.update(
              { doc: { content: content_elasticsearch_document } },
              { _id: item.id, _routing: item.memex_project_id, retry_on_conflict: 3 }
            )
          end
        end

        [result]
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        return [] unless content.present?
        project_items_for_content.pluck(:memex_project_id).uniq
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [content, *project_items_for_content]
      end

      # Override ContentHelpers#project_items_for_content to avoid PrefillAssociations.
      # Field::Closed only reads item.issue_closed_at (a denormalized column), so prefilling
      # the :content association on items is not needed in this processor.
      sig { override.returns(T::Array[MemexProjectItem]) }
      memoize public def project_items_for_content
        raise CanonicalDataMissingError unless content.present?
        T.must(content).memex_project_items.to_a
      end

      sig { returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::Content)) }
      memoize private def content_elasticsearch_document
        content&.memex_content_elasticsearch_document
      end

      # Shared bulk params for both branches of `#update`, so the
      # `bulk_refresh_strategy` decision is honored consistently.
      sig { returns(Elastomer::Interfaces::Api::Bulk::Request::Params) }
      memoize private def bulk_params
        Elastomer::Interfaces::Api::Bulk::Request::Params.new(refresh: bulk_refresh_strategy)
      end

      sig { returns(T::Boolean) }
      private def closed_timestamp_topic?
        CLOSED_TIMESTAMP_TOPICS.any? { |t| @message.topic.match?(t) }
      end

      sig { returns(Integer) }
      private def content_id
        T.must(pull_request_id || issue_id)
      end

      sig { returns(String) }
      private def content_type
        return "PullRequest" if pull_request_id
        "Issue"
      end

      sig { returns(T.nilable(Integer)) }
      private def pull_request_id
        @message.dig(:pull_request, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def issue_id
        @message.dig(:issue, :id_value)
      end

      sig { returns(Integer) }
      private def repository_id
        @message.dig(:repository, :id)
      end
    end
  end
end
