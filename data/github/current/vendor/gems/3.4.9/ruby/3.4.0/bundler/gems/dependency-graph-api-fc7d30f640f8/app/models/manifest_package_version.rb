class ManifestPackageVersion < ApplicationRecord
  self.table_name = "dg_manifest_package_versions"

  has_many :manifest_entries
  belongs_to :manifest_package

  delegate :package_manager, :package_name, to: :manifest_package

  def requirement_set
    @requirement_set ||= Versioning::RequirementSet
      .deserialize(requirements, allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager))
  end
end
