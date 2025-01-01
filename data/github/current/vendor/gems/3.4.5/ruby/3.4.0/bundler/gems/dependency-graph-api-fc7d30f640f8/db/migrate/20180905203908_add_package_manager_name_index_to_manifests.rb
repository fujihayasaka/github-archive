class AddPackageManagerNameIndexToManifests < ActiveRecord::Migration[5.0]
  def change
    add_index :dg_manifests, [:package_manager, :name]
  end
end
