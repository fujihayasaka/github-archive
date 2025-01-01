class FixManifestDependencyIndex2 < ActiveRecord::Migration[5.2]
  def change
    remove_index :dg_manifest_dependencies, column: [:package_manager, :package_name, :exact_version, :manifest_id], name: "index_dg_manifest_dependencies_on_pkg_mgr_name_version_manifest"

    add_index :dg_manifest_dependencies, [:manifest_id, :package_manager, :package_name, :exact_version], name: "index_dg_manifest_dependencies_on_manifest_pkg_mgr_name_version"

  end
end
