class FixManifestDependencyIndex < ActiveRecord::Migration[5.2]
  def change
    remove_index :dg_manifest_dependencies, [:package_name, :id]

    add_index :dg_manifest_dependencies, [:package_name], name: :index_dg_manifest_dependencies_on_package_name_and_id

    remove_index :dg_manifest_dependencies, column:  [:package_name, :encoded_lower_bound, :encoded_upper_bound, :id], name: :index_manifest_dep_spec_version_ranges
    add_index :dg_manifest_dependencies, [:package_name, :encoded_lower_bound, :encoded_upper_bound], name: :index_manifest_dep_spec_version_ranges

    remove_index :dg_manifest_dependencies, [:manifest_id]
  end
end
