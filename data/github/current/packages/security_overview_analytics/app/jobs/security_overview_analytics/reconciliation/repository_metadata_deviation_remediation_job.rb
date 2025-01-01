# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Reconciliation
    class RepositoryMetadataDeviationRemediationJob < ApplicationJob
      extend T::Sig

      RepositoryMetadata = ::SecurityOverviewAnalytics::Repository

      queue_as :security_overview_analytics_repository_metadata_deviation_remediation

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      use_replicas ApplicationRecord::SecurityOverviewAnalytics,
        ApplicationRecord::Repositories,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Configurations,
        ApplicationRecord::Collab

      locked_by timeout: 15.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

      sig { params(session_id: String, repository_id: Integer).void }
      def perform(session_id:, repository_id:)
        repository_metadata = RepositoryMetadata.find_by(repository_id:)
        repository = ::Repositories::Public.get_active_or_deleted(repository_id)
        remediation = :no_op

        if should_store_repository_metadata?(repository:)
          if repository_metadata.present?
            owner_type = repository&.owner&.type&.upcase
            business_id = repository.nil? ? nil : BusinessResolver.resolve_for(repository)&.id
            with_throttle_and_write do
              repository_metadata.update(
                organization_id: owner_type == "USER" ? 0 : repository&.owner_id,
                owner_id: repository&.owner_id,
                owner_type: owner_type,
                business_id: business_id,
                name: repository&.name,
                visibility: repository&.visibility,
                archived: repository&.archived?,
                event_time: Time.current
              )
            end
            remediation = :metadata_updated
          else
            owner_type = repository&.owner&.type&.upcase
            business_id = repository.nil? ? nil : BusinessResolver.resolve_for(repository)&.id
            with_throttle_and_write do
              RepositoryMetadata.upsert({
                repository_id: repository&.id,
                organization_id: owner_type == "USER" ? 0 : repository&.owner_id,
                owner_id: repository&.owner_id,
                owner_type: owner_type,
                business_id: business_id,
                name: repository&.name,
                visibility: repository&.visibility,
                archived: repository&.archived?,
                event_time: Time.current
              }, on_duplicate: :skip)
            end
            remediation = :metadata_created
          end
        elsif repository_metadata.present?
          with_throttle_and_write do
            repository_metadata.destroy!
          end
          remediation = :metadata_deleted
        end

        GitHub.logger.info(
          "Deviation remediation completed.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.deviation.remediation": remediation
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.repository_metadata_deviation_remediation.completed",
          tags: all_stats_tags + ["remediation:#{remediation}"]
        )
      end

      protected

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.repo.id": arguments.dig(0, :repository_id),
          "gh.security_overview_analytics.job.session_id": arguments.dig(0, :session_id)
        })
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({
          app: "github-security-center"
        })
      end

      private

      sig { params(repository: T.nilable(::Repository)).returns(T::Boolean) }
      def should_store_repository_metadata?(repository:)
        return false if repository.nil?
        return false if repository.deleted?

        owner = repository.owner
        return false if owner.nil?

        return false unless TenantValidationHelper.is_owner_in_scope?(owner)
        Initialization.for(owner).initialized?(type: Initialization::Type::RepositoryMetadata)
      end

      sig { params(block: T.proc.void).void }
      def with_throttle_and_write(&block)
        RepositoryMetadata.throttle do
          with_write do
            yield
          end
        end
      end
    end
  end
end
