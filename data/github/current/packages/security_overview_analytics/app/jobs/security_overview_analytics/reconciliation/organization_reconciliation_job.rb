# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Reconciliation
    class OrganizationReconciliationJob < ApplicationJob
      extend T::Sig
      include GitHub::Memoizer
      include FanoutThrottler

      queue_as :security_overview_analytics_tenant_reconciliation

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      use_replicas ApplicationRecord::SecurityOverviewAnalytics,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Configurations

      # Allow concurrent jobs of different metric types
      locked_by timeout: 15.minutes, key: ->(job) do
        organization_id = job.arguments.dig(0, :organization_id)
        DEFAULT_LOCK_STRINGIFY_PROC.call([organization_id])
      end

      RECONCILIATION_EVENT = T.let("security_overview_analytics.reconciliation", String)

      sig { params(source_event: String).returns(T::Boolean) }
      def self.is_reconciliation_event?(source_event)
        RECONCILIATION_EVENT == source_event
      end

      sig { params(organization_id: Integer, type: T.nilable(String)).void }
      def perform(organization_id:, type: nil)
        # If we are reconciling a specific type, only reconcile that type.
        # Otherwise reconcile all types.
        types_to_reconcile = Initialization::ScopeStrategy::Organization.available_initialization_types
        types_to_reconcile &= [Initialization::Type.deserialize(type)] if type.present?

        types_to_reconcile.each do |type|
          session = session(type.serialize)
          # TODO - lock session here after removing the logic from fanout
          next unless should_reconcile?(session, type)

          case type
          when Initialization::Type::FeatureEnablement
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id:)
          when Initialization::Type::RepositoryMetadata
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id:)
          when Initialization::Type::CodeScanningAlert
            CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id:)
          when Initialization::Type::SecretScanningAlert
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id:)
          when Initialization::Type::DependabotAlerts
            DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id:)
          when Initialization::Type::Organizations, Initialization::Type::Users
            # These types are not handled at the repository level.
          when Initialization::Type::Unknown
            # valid_values should never include Unknown.
            # However, without having a case for it, Sorbet's exhaustiveness checking does not work.
          else
            T.absurd(type)
          end
        end
      end

      sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
      def fanout_jobs
        # If any of the below job queue is being throttled, delay the entire batch.
        [
          RepositoryMetadataDeviationDetectionJob,
          RepositoryFeatureStatusDeviationDetectionJob,
          DependabotRepositoriesDeviationDetectionJob,
          CodeScanningRepositoriesDeviationDetectionJob,
          SecretScanningRepositoriesDeviationDetectionJob,
        ]
      end

      protected

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.org.id": organization_id,
          "gh.security_overview_analytics.reconciliation.type": arguments.dig(0, :type)
        })
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({
          app: "github-security-center"
        })
      end

      private

      sig { returns(Integer) }
      memoize def organization_id
        arguments.dig(0, :organization_id)
      end

      sig { params(type: String).returns(Reconciliation::Session) }
      def session(type)
        Reconciliation::Session.new(owner_id: organization_id, type:)
      end

      sig { params(session: Reconciliation::Session, type: Initialization::Type).returns(T::Boolean) }
      def should_reconcile?(session, type)
        organization = ::Organization.find_by!(id: organization_id)

        unless TenantValidationHelper.is_owner_in_scope?(organization)
          GitHub.logger.info(
            "Organization reconciliation skipped.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.job.reason": "Tenant not in scope.",
          )
          GitHub.dogstats.increment(
            "security_overview_analytics.organization_reconciliation.skipped",
            tags: all_stats_tags + ["reason:tenant_not_in_scope"]
          )
          return false
        end

        unless Initialization.for(organization).initialized?(type:)
          GitHub.logger.info(
            "Organization reconciliation skipped.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.job.reason": "Tenant not initialized."
          )

          GitHub.dogstats.increment(
            "security_overview_analytics.organization_reconciliation.skipped",
            tags: all_stats_tags + ["reason:tenant_not_initialized"]
          )
          return false
        end

        # TODO - validate session locking here (https://github.com/github/security-center/issues/4133)

        true
      end
    end
  end
end
