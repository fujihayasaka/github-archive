# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class IncrementRegistryPackageDownloadCount < Platform::Mutations::Base
      description "increments the download count for a package by 1."
      visibility :internal
      minimum_accepted_scopes ["read:packages"]

      argument :package_version_id, ID, "The Package Version ID to log a download.", required: true, loads: Objects::PackageVersion

      field :package_version_id, ID, "The Package Version ID to log a download.", null: true

      def resolve(package_version:, **inputs)
        raise Errors::Validation.new("Version not found.") unless package_version

        Registry::PackageDownloadActivity.track(package_version.registry_package_id, package_version.id, Time.now.change(min: 0, sec: 0))

        publish_download_hydro_event package_version

        # This event is being published for migration scenario to V2 when package is in migration state
        # more details: https://github.com/github/c2c-package-registry/issues/5023
        publish_download_hydro_event_v2_migration package_version

        { package_version_id: package_version.global_relay_id }
      end

      def rms_migrator_client
        @rms_migrator_client ||= PackageRegistry::Twirp.migrator_client
      end

      def publish_download_hydro_event_v2_migration(package_version)
        if package_version.migration_state == "complete" && should_sync_download_count(package_version)
          namespace = context[:viewer].login if context[:viewer].present?

          reponame = package_version.package&.repository.name if package_version.package&.repository.present?
          pkgname = package_version.package.name if package_version.package.present?
          v2_pkg_name = "#{reponame}/#{pkgname}"

          tagname = package_version.version if package_version.version.present?

          rms_migrator_client.emit_migration_download_event?(namespace: namespace, package_name: v2_pkg_name, version_name: tagname)
        end

      end

      def get_total_downloads(package_version)
        count = package_version&.total_download_count
        return count.to_i if count.present?
        0
      end

      def should_sync_download_count(package_version)
        total_downloads = get_total_downloads(package_version)
        if total_downloads > 0 && package_version.files_count > 0
          mod = total_downloads.modulo(package_version.files_count)
          return true if mod == 0
        end
        false
      end

      def publish_download_hydro_event(package_version)
        params = {
          repository: package_version.package&.repository,
          registry_package_id: package_version.package&.id,
          version: package_version.version,
          actor: context[:viewer],
          action: "DOWNLOADED",
          user_agent: GitHub.context[:user_agent].to_s,
        }

        GlobalInstrumenter.instrument("package.downloaded", params)
      end
    end
  end
end
