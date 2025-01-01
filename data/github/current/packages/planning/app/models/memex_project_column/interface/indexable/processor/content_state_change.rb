# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class ContentStateChange < Base
      include GitHub::Memoizer

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
          /github\.v1\.PullRequestInProgress\Z/,
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
        @index.count_all({ query: es_query }) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        model.present?
      end

      sig { returns(T.nilable(T.any(Issue, PullRequest))) }
      memoize private def model
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
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def update(es_client)
        raise CanonicalDataMissingError unless related_project_items.present? && content_elasticsearch_document.present?

        es_client.bulk do |bulk|
          T.must(related_project_items).each do |item|
            bulk.update(
              { doc: { content: content_elasticsearch_document } },
              { _id: item.id, _routing: item.memex_project_id, retry_on_conflict: 3 }
            )
          end
        end
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        related_project_items&.pluck(:memex_project_id)&.uniq || []
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [model, *related_project_items]
      end

      sig { returns(T.nilable(T::Array[MemexProjectItem])) }
      memoize private def related_project_items
        model&.memex_project_items.to_a
      end

      sig { returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::Content)) }
      memoize private def content_elasticsearch_document
        model&.memex_content_elasticsearch_document
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
        @message.dig(:issue, :id)
      end

      sig { returns(Integer) }
      private def repository_id
        @message.dig(:repository, :id)
      end
    end
  end
end
