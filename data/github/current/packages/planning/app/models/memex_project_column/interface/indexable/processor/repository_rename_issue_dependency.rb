# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class RepositoryRenameIssueDependency < Base
      include GitHub::Memoizer
      include ResyncProjectsStrategy
      include SpecialFieldProcessorHelpers

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.v1\.RepositoryRename\Z/
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

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      def es_query
        previous_nwo = "#{T.must(current_owner)}/#{T.must(previous_name)}"

        {
          bool: {
            should: [
              {
                prefix: {
                  "content.blocking.nwo_reference.keyword" => previous_nwo
                }
              },
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
        @message.dig(:repository, :id)
      end

      sig { returns(T.nilable(String)) }
      memoize def previous_name
        @message.dig(:previous_name)
      end

      sig { returns(T.nilable(String)) }
      memoize def current_name
        @message.dig(:current_name)
      end

      sig { returns(T.nilable(String)) }
      memoize def current_owner
        repository&.owner&.display_login
      end
    end
  end
end
