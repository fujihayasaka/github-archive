# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IssueTypeUpdate < Base
      include GitHub::Memoizer
      include ResyncProjectsStrategy

      BATCH_LIMIT = 1000

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.IssueTypeUpdate\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        issue_type_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        true
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        issue_type.present?
      end

      # The underlying issue type may not be referenced in Elasticsearch if a project was indexed when the issue type
      # was disabled, instead we rely on querying MySQL for projects referencing issues the updated issue type.
      sig { override.returns(T::Array[Integer]) }
      memoize def project_ids_to_resync
        return [] unless (this_issue_type = issue_type)

        project_ids = T.let(Set.new, T::Set[Integer])
        this_issue_type.issues.in_batches(of: BATCH_LIMIT) do |batch|
          additional_project_ids = MemexProjectItem.where(issue_id: batch.pluck(:id)).pluck(:memex_project_id)
          project_ids.merge(additional_project_ids)
        end
        project_ids.to_a
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [issue_type]
      end

      sig { returns(T.nilable(IssueType)) }
      memoize private def issue_type
        IssueType.find_by(id: issue_type_id)
      end

      sig { returns(T.nilable(Integer)) }
      memoize private def issue_type_id
        @message.dig(:issue_type, :id)
      end

    end
  end
end
