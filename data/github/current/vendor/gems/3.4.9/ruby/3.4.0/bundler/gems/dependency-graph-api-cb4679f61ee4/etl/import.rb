class Import < ApplicationRecord
  self.table_name = "dg_etl_imports"

  restrict_type_of :package_manager, to: Types::PackageManager

  enum :stage, package_releases: 0, manifests: 1

  serialize :metadata, type: Hash

  def self.latest
    order(id: :desc).last || new
  end

  def self.for_package_manager(package_manager)
    if package_manager.respond_to?(:serialize)
      package_manager = package_manager.serialize
    end

    where(package_manager: package_manager)
  end
end
