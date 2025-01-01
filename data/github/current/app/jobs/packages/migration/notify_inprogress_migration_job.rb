# typed: false
# frozen_string_literal: true

module Packages
  module Migration
    class NotifyInprogressMigrationJob < ApplicationJob
      queue_as :packages_migration_migrate_namespace

      retry_on_dirty_exit

      schedule interval: 5.minutes, condition: -> { !GitHub.enterprise? }

      # In Proxima we are only using V2 implementation and will not trigger migrations
      # Also the flow operates on owner ids
      exempt_from_tenant_context_requirement

      def perform(*args)
        maven_in_progress_migration_oids_created_at = Registry::OwnerMigration.in_progress_migration("maven").pluck(:owner_id, :created_at)
        maven_owner_ids = []

        maven_in_progress_migration_oids_created_at.map do |ownerids_created_at|
          maven_owner_ids.push(ownerids_created_at[0])
          notify_in_progress_time_exceeded(ownerids_created_at, "maven")
        end

        notify_unmigrated_count(maven_owner_ids, "maven") if maven_owner_ids.length > 0

        notify_unmigrated_count_migrated_namespace("maven")
      end

      def notify_in_progress_time_exceeded(ownerids_created_at, package_type)
        owner_id = ownerids_created_at[0]
        created_at = ownerids_created_at[1]
        time_exceeded = (Time.current - created_at) >= 1.hour
        if time_exceeded
          GitHub.logger.info(
            "Time exceeded for migration",
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.owner_id" => owner_id,
            "gh.registry.job_created_at" => created_at,
            "gh.registry.package_type" => package_type,
          )
        end
      end

      # Notify in progress package migration with unmigrated version present
      def notify_unmigrated_count(owner_ids, package_type)
        unmigrated_version_count = Registry::PackageVersion.joins(:package).where(package: { owner_id: owner_ids, package_type: package_type }).not_migrated.count
        if unmigrated_version_count > 0
          unmigrated_owner_ids = Registry::PackageVersion.joins(:package).where(package: { owner_id: owner_ids, package_type: package_type }).not_migrated.pluck(:owner_id).uniq
          GitHub.logger.info(
            "Unmigrated count for inprogress migration",
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.unmigrated_version_count" => unmigrated_version_count,
            "gh.registry.unmigrated_owner_ids" => unmigrated_owner_ids,
            "gh.registry.package_type" => package_type,
          )
        end
      end

      # Notify migrated owner migration with unmigrated version present
      def notify_unmigrated_count_migrated_namespace(package_type)
        last_5_mins = Time.current - 6.minutes
        owner_ids = Registry::OwnerMigration.migrated_migration(package_type).where("created_at >= ?", last_5_mins).pluck(:owner_id)
        unmigrated_version_count = Registry::PackageVersion.joins(:package).where(package: { owner_id: owner_ids, package_type: package_type }).not_migrated.count
        if unmigrated_version_count > 0
          migrated_owner_ids = Registry::PackageVersion.joins(:package).where(package: { owner_id: owner_ids, package_type: package_type }).not_migrated.pluck(:owner_id).uniq
          GitHub.logger.info(
            "Unmigrated count for migrated owner migration",
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.unmigrated_version_count" => unmigrated_version_count,
            "gh.registry.migrated_owner_ids" => migrated_owner_ids,
            "gh.registry.package_type" => package_type,
          )
        end
      end

    end
  end
end
