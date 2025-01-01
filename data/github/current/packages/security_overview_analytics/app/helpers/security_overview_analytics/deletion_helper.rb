# typed: strict
# frozen_string_literal: true

require_relative "../../../../security_products/app/models/security_center/k_v"

module SecurityOverviewAnalytics
  class DeletionHelper
    extend T::Helpers
    extend T::Sig

    abstract!
    sealed!

    BusinessStrategy = T.type_alias { T.class_of(::SecurityOverviewAnalytics::Initialization::ScopeStrategy::Business) }
    OrganizationStrategy = T.type_alias { T.class_of(::SecurityOverviewAnalytics::Initialization::ScopeStrategy::Organization) }

    sig { params(business_ids: T::Array[Integer], type: T.nilable(Initialization::Type)).void }
    def self.delete_all_for_businesses(business_ids: [], type: nil)
      business_ids.each_slice(1_000).each do |ids|

        # Delete organization metrics.
        ::Organization
          .includes(:business)
          .where(businesses: { id: ids })
          .in_batches do |batch|
            delete_all_for_organizations(organization_ids: batch.pluck(:id), type:)
          end

        # Delete initialization kv entries
        # This is intentionally delayed until after the records are removed from Analytics due to
        # block any attempt to start a backfill by visiting business or org level pages.
        delete_kv_entries(ids, ::SecurityOverviewAnalytics::Initialization::ScopeStrategy::Business, type:)
      end

      GitHub.dogstats.count("security_overview_analytics.reset.businesses_processed", business_ids.size)
    end

    sig { params(organization_ids: T::Array[Integer], type: T.nilable(Initialization::Type)).void }
    def self.delete_all_for_organizations(organization_ids: [], type: nil)
      organization_ids.each_slice(1_000).each do |ids|
        # If we are deleting a specific type, only delete that type.
        # Otherwise delete all types.
        types_to_delete = Initialization::Type.all
        types_to_delete &= [type] if type.present?

        # Delete
        #   - ::SecurityOverviewAnalytics::FeatureStatusRevision
        #   - ::SecurityOverviewAnalytics::DependabotAlertRevision
        #   - ::SecurityOverviewAnalytics::CodeScanningAlertRevision
        #   - ::SecurityOverviewAnalytics::SecretScanningAlertRevision
        #   - ::SecurityOverviewAnalytics::Repository
        soa_repos_rel = ::SecurityOverviewAnalytics::Repository.where(organization_id: organization_ids)
        soa_repos_rel.in_batches do |soa_repo_batch|
          if types_to_delete.include?(Initialization::Type::FeatureEnablement)
            ::SecurityOverviewAnalytics::FeatureStatusRevision
              .where(repository_id: soa_repo_batch)
              .in_batches do |rev_batch|
                ::SecurityOverviewAnalytics::FeatureStatusRevision.throttle_writes_with_retry do
                  rev_batch.delete_all

                  GitHub.dogstats.count("security_overview_analytics.reset.feature_status_revisions.deleted", rev_batch.size)
                end
              end
          end

          if types_to_delete.include?(Initialization::Type::DependabotAlerts)
            ::SecurityOverviewAnalytics::DependabotAlertRevision
              .where(repository_id: soa_repo_batch)
              .in_batches do |rev_batch|
                ::SecurityOverviewAnalytics::DependabotAlertRevision.throttle_writes_with_retry do
                  rev_batch.delete_all

                  GitHub.dogstats.count("security_overview_analytics.reset.dependabot_alert_revisions.deleted", rev_batch.size)
                end
              end
          end

          if types_to_delete.include?(Initialization::Type::CodeScanningAlert)
            ::SecurityOverviewAnalytics::CodeScanningAlertRevision
              .where(repository_id: soa_repo_batch)
              .in_batches do |rev_batch|
                ::SecurityOverviewAnalytics::CodeScanningAlertRevision.throttle_writes_with_retry do
                  rev_batch.delete_all

                  GitHub.dogstats.count("security_overview_analytics.reset.code_scanning_alert_revisions.deleted", rev_batch.size)
                end
              end
          end

          if types_to_delete.include?(Initialization::Type::SecretScanningAlert)
            ::SecurityOverviewAnalytics::SecretScanningAlertRevision
              .where(repository_id: soa_repo_batch)
              .in_batches do |rev_batch|
                ::SecurityOverviewAnalytics::SecretScanningAlertRevision.throttle_writes_with_retry do
                  rev_batch.delete_all

                  GitHub.dogstats.count("security_overview_analytics.reset.secret_scanning_alert_revisions.deleted", rev_batch.size)
                end
              end
          end

          if types_to_delete.include?(Initialization::Type::RepositoryMetadata)
            ::SecurityOverviewAnalytics::Repository.throttle_writes_with_retry do
              soa_repo_batch.delete_all

              GitHub.dogstats.count("security_overview_analytics.reset.repo_metadata.deleted", soa_repo_batch.size)
            end
          end
        end

        # Delete initialization kv entries
        # This is intentionally delayed until after the records are removed from Analytics due to
        # block any attempt to start a backfill by visiting business or org level pages.
        delete_kv_entries(ids, ::SecurityOverviewAnalytics::Initialization::ScopeStrategy::Organization, type:)
      end

      GitHub.dogstats.count("security_overview_analytics.reset.orgs_processed", organization_ids.size)
    end

    sig do
      params(
        ids: T::Array[Integer],
        strategy: T.any(BusinessStrategy, OrganizationStrategy),
        type: T.nilable(Initialization::Type),
      ).void
    end
    def self.delete_kv_entries(ids, strategy, type: nil)
      ids.map do |id|
        if type.present?
          key = strategy.initialization_kv_key(id: id, type:)
          ThrottleHelper.throttle_kv_writes_with_fallback do
            # TODO move init keys out of global KV https://github.com/github/security-center/issues/3801
            SecurityCenter::KV.store.del(key)
          end
        else
          strategy.available_metric_keys(id:).map do |key|
            ThrottleHelper.throttle_kv_writes_with_fallback do
              # TODO move init keys out of global KV https://github.com/github/security-center/issues/3801
              SecurityCenter::KV.store.del(key)
            end
          end
        end
      end
    end
  end
end
