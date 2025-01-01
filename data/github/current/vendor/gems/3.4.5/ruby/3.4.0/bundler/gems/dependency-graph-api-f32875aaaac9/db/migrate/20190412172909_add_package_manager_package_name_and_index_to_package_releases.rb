class AddPackageManagerPackageNameAndIndexToPackageReleases < ActiveRecord::Migration[5.2]
  def change
    add_column :dg_package_versions, :package_manager, :integer
    add_column :dg_package_versions, :package_name, :string

    add_index :dg_package_versions, [:package_name, :package_manager, :name],
      name: "index_dg_package_versions_on_package_name_package_manager_name"
  end
end
