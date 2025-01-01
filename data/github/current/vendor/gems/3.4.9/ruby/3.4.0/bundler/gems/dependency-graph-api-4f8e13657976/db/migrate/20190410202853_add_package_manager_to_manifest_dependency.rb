class AddPackageManagerToManifestDependency < ActiveRecord::Migration[5.2]
  def change
    add_column :dg_manifest_dependencies, :package_manager, :integer, null: true
  end
end
