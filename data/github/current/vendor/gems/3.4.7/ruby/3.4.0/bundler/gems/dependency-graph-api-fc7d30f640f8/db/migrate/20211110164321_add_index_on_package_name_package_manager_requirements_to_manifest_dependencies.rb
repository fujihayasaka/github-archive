class AddIndexOnPackageNamePackageManagerRequirementsToManifestDependencies < ActiveRecord::Migration[6.0]
  def change
    add_index :dg_manifest_dependencies, [:package_name, :package_manager, :requirements], name: "index_dg_manifest_dependencies_on_pkg_name_pkg_mgr_reqs", if_not_exists: true
  end
end
