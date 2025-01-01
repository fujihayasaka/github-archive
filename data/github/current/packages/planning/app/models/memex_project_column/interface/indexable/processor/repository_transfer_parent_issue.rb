# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class RepositoryTransferParentIssue < Base
      include GitHub::Memoizer
      include ResyncProjectsStrategy

      BATCH_LIMIT = 1000

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.repositories\.v1\.Transferred\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        Issue.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        repository_id.present?
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        true
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        repository.present?
      end

      sig { override.returns(T::Array[Integer]) }
      memoize def project_ids_to_resync
        return [] unless (this_repository = repository)

        project_ids = T.let(Set.new, T::Set[Integer])
        sub_issues = SubIssue.where(source_repository_id: this_repository.id)

        sub_issues.in_batches(of: BATCH_LIMIT) do |batch|
          issue_ids = batch.pluck(:target_issue_id).uniq
          additional_project_ids = MemexProjectItem.where(issue_id: issue_ids).pluck(:memex_project_id)
          project_ids.merge(additional_project_ids)
        end

        project_ids.to_a
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [repository]
      end


      sig { returns(T.nilable(Repository)) }
      memoize private def repository
        if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
          return unless id = repository_id
          T.cast(Repositories.domain.by_id(id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
        else
          Repository.find_by(id: repository_id)
        end
      end

      sig { returns(T.nilable(Integer)) }
      memoize private def repository_id
        @message.dig(:repository_id)
      end
    end
  end
end
