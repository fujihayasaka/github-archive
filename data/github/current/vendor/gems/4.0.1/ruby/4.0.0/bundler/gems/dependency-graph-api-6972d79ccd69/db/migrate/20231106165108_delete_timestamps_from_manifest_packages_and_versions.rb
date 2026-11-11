class DeleteTimestampsFromManifestPackagesAndVersions < ActiveRecord::Migration[7.0]
  def change
    remove_column :dg_manifest_packages, :created_at, :datetime
    remove_column :dg_manifest_packages, :updated_at, :datetime

    remove_column :dg_manifest_package_versions, :created_at, :datetime
    remove_column :dg_manifest_package_versions, :updated_at, :datetime
  end
end
