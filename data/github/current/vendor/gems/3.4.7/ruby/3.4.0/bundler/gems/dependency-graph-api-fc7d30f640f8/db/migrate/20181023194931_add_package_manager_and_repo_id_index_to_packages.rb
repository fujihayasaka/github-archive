class AddPackageManagerAndRepoIdIndexToPackages < ActiveRecord::Migration[5.0]
  def change
    add_index :dg_packages, [:package_manager, :repository_id]
  end
end
