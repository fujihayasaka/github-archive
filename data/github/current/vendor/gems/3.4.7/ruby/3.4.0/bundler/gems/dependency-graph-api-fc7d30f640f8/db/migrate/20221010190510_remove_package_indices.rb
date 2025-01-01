class RemovePackageIndices < ActiveRecord::Migration[6.0]
  def change
    remove_index :dg_package_versions, [:repository_id]
    remove_index :dg_packages, [:last_published_at]
  end
end
