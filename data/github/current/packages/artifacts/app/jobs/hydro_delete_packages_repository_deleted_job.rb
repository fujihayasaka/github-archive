# typed: true
# frozen_string_literal: true

class HydroDeletePackagesRepositoryDeletedJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_delete_packages_repository_deleted

  # Public: process a Hydro message
  #
  # Returns nothing
  def perform
    repository.packages.find_each do |package|
      package.package_versions.not_deleted.find_each do |version|
        begin
          Registry::PackageVersion.throttle do
            with_write do
              version.delete!(actor: repository.deleted_by, force_delete: true)
            end
          end
        rescue ActiveRecord::ActiveRecordError => e
          Failbot.report(e)
        end
      end
    end
  end
end
