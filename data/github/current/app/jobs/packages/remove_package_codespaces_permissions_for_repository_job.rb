# typed: true
# frozen_string_literal: true

module Packages
  class RemovePackageCodespacesPermissionsForRepositoryJob < ApplicationJob
    queue_as :package_codespaces_permissions_job

    retry_on_dirty_exit

    def perform(repository_id:, package_id:, user_id:, entry_point:)
      repository = Repositories::Public.get_active_or_deleted!(repository_id)
      codespace_ids = Codespace.where(repository_id: repository.id).pluck(:id)

      # Packages Permissions Availability
      #
      # TODO: Keep this until we know what to do with Codespaces.
      # See https://github.com/github/package-registry-team/issues/7344
      codespace_ids.in_groups_of(100, false) do |group|
        Codespace.active_installations_for(group).find_each do |installation|
          Permissions::Service.throttle_writes_in_background_with_retry do
            package = PackageRegistry::PackageSubject.new(id: package_id, access_type: :contents)
            SiteScopedIntegrationInstallation::Editors::Packages.revoke(installation, package, entry_point:)
          end
        end
      end
    end
  end
end
