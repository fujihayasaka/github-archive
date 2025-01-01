# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Packages
  class AppendPackageCodespacesPermissionsForRepositoryJob < ApplicationJob
    queue_as :package_codespaces_permissions_job

    retry_on_dirty_exit

    # Packages Permissions Availability
    #
    # TODO: Keep this until we know what to do with Codespaces.
    # See https://github.com/github/package-registry-team/issues/7344
    def perform(repository_id:, package_id:, user_id:, entry_point:)
      repository = Repositories::Public.find_active!(repository_id)
      codespace_ids = Codespace.where(repository_id: repository.id).pluck(:id)

      codespace_ids.in_groups_of(100, false) do |group|
        Codespace.active_installations_for(group).find_each do |installation|
          Permissions::Service.throttle_writes_in_background_with_retry do
            package = PackageRegistry::PackageSubject.new(id: package_id, access_type: :contents)
            SiteScopedIntegrationInstallation::Editors::Packages.grant(installation, package, entry_point:)
          end
        end
      end
    end
  end
end
