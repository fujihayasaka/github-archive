class AddIndexPackageVersionsOnPackageAndRepository < ActiveRecord::Migration[6.0]
  def change
    add_index :dg_package_versions,
              [:package_id, :repository_id],
              name: "index_dg_package_versions_on_package_id_and_repo_id"
  end
end
