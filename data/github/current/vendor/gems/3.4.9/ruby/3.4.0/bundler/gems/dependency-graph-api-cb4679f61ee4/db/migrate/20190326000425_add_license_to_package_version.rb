class AddLicenseToPackageVersion < ActiveRecord::Migration[5.2]
  def change
    add_column :dg_package_versions, :license, :string
    add_column :dg_package_versions, :clearly_defined_score, :integer

    add_index :dg_package_versions, :license
  end
end
