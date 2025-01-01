class AddRequirementsToUniqueIndex < ActiveRecord::Migration[6.0]
  def change
    add_index(:dg_manifest_dependencies, [:manifest_id, :package_name, :requirements],
      unique: true,
      name: :manifest_dep_spec_package_name_reqs,
      if_not_exists: true
    )

    remove_index :dg_manifest_dependencies, name: :manifest_dep_spec_package_name, if_exists: true
  end
end
