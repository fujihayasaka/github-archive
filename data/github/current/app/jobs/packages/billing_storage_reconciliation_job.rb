# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

#
# This is a background job that is supposed to be used in conjunction with staff tools:
#
# In some cases, storage usage for customers using Docker in GH Packages are reporting
# incorrect usage values which prevent them from continuing to use our product.
#
# Since we don't fully understand where these differences come from, we implemented
# This job so support staff can correct the difference for now.

module Packages
  class BillingStorageReconciliationJob < ApplicationJob

    queue_as :billing_storage_reconciliation

    retry_on_dirty_exit
    discard_on ActiveRecord::RecordNotFound

    def perform(user_id:)
      return unless GitHub.billing_enabled?

      user = User.find(user_id)
      repositories = user.repositories.private_scope

      billing_differences = repositories.map { |repo| billing_difference(user: user, repository: repo) }
      billing_differences.each do |diff|
        submit_billing_difference(**diff)
      end

      correct_packages_v2_billing_difference(user: user)
    end

    private

    def billing_difference(user:, repository:)
      storage_usage = ::Registry::StorageUsage.new(owner: user, repository: repository)

      combined_usage = storage_usage.billing_combined_usage
      actions_usage = storage_usage.billing_actions_usage
      known_packages_usage = storage_usage.packages_usage

      # Combined usage = actions usage + known packages usage + overcharged usage
      overcharged_usage = combined_usage - actions_usage - known_packages_usage

      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.packages.user_name" => user.name,
        "gh.packages.repository_name" => repository.name,
        "gh.packages.actions_usage" => actions_usage,
        "gh.packages.combined_usage" => combined_usage,
        "gh.packages.known_packages_usage" => known_packages_usage,
        "gh.packages.overcharged_usage" => overcharged_usage,
      )

      { user: user, repository: repository, difference: overcharged_usage }
    end

    def submit_billing_difference(user:, repository:, difference:)
      return unless difference.positive?

      fake_package = Registry::Package.new(
        id: 0, # some ID value is required for populating the global_id field in a hydro payload
        name: "BillingStorageDelete",
        owner: user,
        repository: repository,
        package_type: :docker,
        # Message serializers depend on this timestamp to be there
        created_at: Time.now.utc,
        updated_at: Time.now.utc,
      )

      fake_version = Registry::PackageVersion.new(
        id: 0, # some ID value is required for populating the global_id field in a hydro payload
        package: fake_package,
        version: "1.3.3.7-delete",
        author: user,
        # Message serializers depend on this timestamp to be there
        created_at: Time.now.utc,
        updated_at: Time.now.utc,
      )

      delete_package_version_data = {
        actor: nil,
        package: fake_package,
        version: fake_version,
        size: difference,
        files_count: 1,
        deleted_at: Time.now,
        storage_service: "AWS_S3",
        user_agent: nil,
        via_actions: false,
      }

      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.packages.user_name" => user.name,
        "gh.packages.repository_name" => repository.name,
        "gh.packages.billing_difference" => difference,
      )

      if FeatureFlag.vexi.enabled?(:packages_submit_billing_reconciliation, user, default: false)
        GitHub.dogstats.increment("packages.billing_reconciliation.corrected_repos")
        GlobalInstrumenter.instrument("package_registry.package_version_deleted", delete_package_version_data)
      end
    end

    def correct_packages_v2_billing_difference(user:)
      storage_usage = ::Registry::StorageUsage.new(owner: user, repository: nil)

      billed_usage = storage_usage.billing_packages_v2_usage
      known_usage = storage_usage.packages_v2_usage

      difference = billed_usage - known_usage

      return unless difference.positive?

      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.packages.user_name" => user.name,
        "gh.packages.billing_difference" => difference,
      )

      return unless FeatureFlag.vexi.enabled?(:packages_submit_billing_reconciliation, user, default: false)

      GitHub.dogstats.increment("packages.billing_reconciliation.corrected_v2_usage")

      ActiveRecord::Base.connected_to(role: :writing) do
        ::Billing::SharedStorage::ArtifactEvent.throttle_with_retry(max_retry_count: 5) do
          ::Billing::SharedStorage::ArtifactEvent.create!(
            owner_id: user.id,
            repository_id: nil,
            effective_at: Time.now,
            source: :packages_v2,
            repository_visibility: :private,
            event_type: :remove,
            size_in_bytes: difference,
            source_artifact_id: 0,
          )
        end
      end
    end
  end
end
