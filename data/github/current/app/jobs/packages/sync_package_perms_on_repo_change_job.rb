# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

#
# This background job runs every time a change is made to repository permissions.
#
# It calls out to the registry metadata service via twirp to list v2 registry packages
# linked to the repo, and updates the permissions for all packages which have active
# permission syncing enabled.

module Packages
  class SyncPackagePermsOnRepoChangeJob < ApplicationJob
    queue_as :sync_package_perms_on_repo_change

    retry_on_dirty_exit
    discard_on ActiveRecord::RecordNotFound

    def perform(repository:)
      # Return if packages are not enabled
      return if !GitHub.packages_enabled?

      packages = PackageRegistry::Twirp.metadata_client.get_packages_by_repo(repo_id: repository.id).packages

      # Filter to packages with active sync enabled
      active_sync_packages = packages.select { |p| p.active_sync_perms }

      with_write do
        # For each package with active sync enabled, synchronize access to repo current state
        active_sync_packages.each do |package|
          PackageRegistry::Package.new(package).sync_access_from_repo(repository: repository)
        end
      end
    end
  end
end
