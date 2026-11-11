class AddPackageNameIndexToManifestDependencies < ActiveRecord::Migration[5.0]
  def change
    add_index :dg_manifest_dependencies, [:package_name, :id]
  end
end
