class DropPackageAndReleaseNwo < ActiveRecord::Migration[6.0]
  def change
    remove_column :dg_packages, :repository_nwo, :string
    remove_column :dg_package_versions, :repository_nwo, :string
  end
end
