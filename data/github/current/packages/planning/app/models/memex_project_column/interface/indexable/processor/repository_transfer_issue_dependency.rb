# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class RepositoryTransferIssueDependency < Base
      include GitHub::Memoizer
      include ResyncProjectsStrategy
      include SpecialFieldProcessorHelpers

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
        return false unless (repository_id = self.repository_id)
        repository_id > 0
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
        project_ids_from_elasticsearch(query: es_query)
      end

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [repository]
      end

      private

      # Returns the Elasticsearch query to find all MemexProjectItems that have a blocking or blocked_by
      # nwo_reference which matches the transferred repository's name-with-owner (NWO) reference.
      sig { returns(T::Hash[T::untyped, T::untyped]) }
      def es_query
        # The transferred repository's old name-with-owner (NWO) reference, like `github/repo`.
        previous_nwo = "#{T.must(previous_owner)}/#{T.must(previous_name)}"

        # Find all project items that have dependencies involving the transferred repository.
        # This includes:
        # 1. Items that have dependencies pointing TO the transferred repository (nwo_reference starts with old repo)
        # 2. Items that contain issues FROM the transferred repository and have ANY dependencies
        {
          bool: {
            should: [
              # Case 1: Items that have blocking dependencies with nwo_reference starting with the old repository NWO
              {
                prefix: {
                  "content.blocking.nwo_reference.keyword" => previous_nwo
                }
              },
              # # Case 2: Items that have blocked_by dependencies with nwo_reference starting with the old repository NWO
              {
                prefix: {
                  "content.blocked_by.nwo_reference.keyword" => previous_nwo
                }
              },
            ]
          }
        }
      end

      sig { returns(T.nilable(Repository)) }
      memoize def repository
        if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
          return unless id = repository_id
          T.cast(Repositories.domain.by_id(id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
        else
          Repository.find_by(id: repository_id)
        end
      end

      sig { returns(T.nilable(Integer)) }
      memoize def repository_id
        @message.dig(:repository_id)
      end

      sig { returns(T.nilable(String)) }
      memoize def previous_name
        @message.dig(:previous_name)
      end

      sig { returns(T.nilable(String)) }
      memoize def previous_owner
        @message.dig(:previous_owner, :login)
      end
    end
  end
end
