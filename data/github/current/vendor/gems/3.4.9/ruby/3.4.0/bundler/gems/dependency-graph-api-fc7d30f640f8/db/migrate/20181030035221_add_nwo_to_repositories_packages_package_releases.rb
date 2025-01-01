class AddNwoToRepositoriesPackagesPackageReleases < ActiveRecord::Migration[5.0]
  def change
    add_column :dg_packages, :repository_nwo, :string
    add_column :dg_package_versions, :repository_nwo, :string
    add_column :dg_repositories, :nwo, :string

    add_index :dg_packages, [:repository_nwo]
    add_index :dg_package_versions, [:repository_nwo]
    add_index :dg_repositories, [:nwo, :public]
  end
end
