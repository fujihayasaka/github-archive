class ManifestPackage < ApplicationRecord
  self.table_name = "dg_manifest_packages"

  has_many :manifest_package_versions

  restrict_type_of :package_manager, to: Types::PackageManager
end
