class AddSourceUrlToPackageVersions < ActiveRecord::Migration[6.0]
  def change
    add_column :dg_package_versions, :source_url, :string
  end
end
