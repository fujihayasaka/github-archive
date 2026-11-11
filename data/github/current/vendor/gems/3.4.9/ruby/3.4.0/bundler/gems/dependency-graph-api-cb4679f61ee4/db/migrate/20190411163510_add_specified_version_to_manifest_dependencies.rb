class AddSpecifiedVersionToManifestDependencies < ActiveRecord::Migration[5.2]
  def change
     add_column :dg_manifest_dependencies, :exact_version, :string, null: true
     add_index :dg_manifest_dependencies, [:package_manager, :package_name, :exact_version, :manifest_id], name: "index_dg_manifest_dependencies_on_pkg_mgr_name_version_manifest"
  end
end
