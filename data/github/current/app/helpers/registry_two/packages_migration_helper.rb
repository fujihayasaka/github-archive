# typed: true
# frozen_string_literal: true

module RegistryTwo
  module PackagesMigrationHelper
    include ActiveSupport::Concern

    def fetch_namespaces(unmigrated_only: false, failed_only: false, error_only: false, migrated_only: false, unmigrated_and_inprogress: false, query: nil)
      namespaces = []
      package_count = 0
      if error_only
        # Fetch unmigrated + retriable_error + pending
        packages = Registry::Package.where("package_type = 3").joins(:package_versions).merge(Registry::PackageVersion.unmigrated).group("owner_id")
      else
        packages = Registry::Package
          .migratable("docker", unmigrated_only: unmigrated_only, failed_only: failed_only, error_only: error_only, migrated_only: migrated_only, unmigrated_and_inprogress: unmigrated_and_inprogress)
          .group("owner_id")
      end

      packages.find_each do |package|
        if (namespace = package.owner) && namespace.name && !namespaces.include?(namespace)
          if error_only
            count = namespace.packages.where(package_type: "docker").joins(:package_versions).merge(Registry::PackageVersion.unmigrated).distinct.count
          else
            count = namespace.packages
              .migratable("docker", unmigrated_only: unmigrated_only, failed_only: failed_only, error_only: error_only, migrated_only: migrated_only, unmigrated_and_inprogress: unmigrated_and_inprogress)
              .count
          end

          if namespace.type == "Organization" && (query.nil? || (namespace.login.include? query))
            namespaces.push(namespace)
            GitHub.logger.info(
              "Found migrateable namespace",
              "gh.registry.namespace" => namespace.name,
              "gh.registry.pkg_count" => count,
            )
            package_count = package_count + count
          end
        end
      end

      [namespaces, package_count]
    end

    def migrate_namespaces(namespaces: nil, force: false, retry_failed: false, unmigrated_package_count: 0, triggered_by: nil)
      return if !namespaces.present?
      GitHub.logger.info(
        "Starting migration for one or more namespaces",
        "code.function" => "migrate_namespaces",
        "code.namespace" => "packages_migration_helper",
        "gh.registry.namespace_count" => namespaces.count,
        "gh.registry.unmigrated_package_count" => unmigrated_package_count
      )

      migration_run = Registry::PackagesMigration.create(total_org_count: namespaces.count, total_pkg_count: unmigrated_package_count, state: :inProgress, owner: triggered_by)
      # Update the header to show progress bar
      channel = GitHub::WebSocket::Channels.packages_migration(migration_run.id)
      GitHub::WebSocket.notify_packages_migration_channel(migration_run, channel)
      GitHub.logger.info(
        "Enqueue namespace job",
        "code.function" => "migrate_namespaces",
        "code.namespace" => "packages_migration_helper",
      )
      namespaces&.each do |namespace|
        ::Packages::Migration::MigrateNamespaceJob.perform_later(namespace, "docker", force: force, retry_failed: retry_failed)
      end
    end

    def key_for_migration_status(repository)
      "immutable_actions_migration_status:repo:#{repository.id}"
    end

    def get_migration_status_value(repository)
      progress_config_key = key_for_migration_status(repository)
      result = ActiveRecord::Base.connected_to(role: :reading) do
        Actions::KV.for_key(progress_config_key).get(progress_config_key).value do
          nil
        end
      end
    end

    def delete_migration_status_key(repository)
      job_key = key_for_migration_status(repository)
      ActiveRecord::Base.connected_to(role: :writing) do
        Actions::KV.for_key(job_key).del(job_key)
      end
    end
  end
end
