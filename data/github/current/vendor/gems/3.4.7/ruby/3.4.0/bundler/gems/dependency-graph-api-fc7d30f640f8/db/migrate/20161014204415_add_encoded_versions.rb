class AddEncodedVersions < ActiveRecord::Migration[5.0]
  def change
    add_column :package_versions, :encoded, :bigint, index: true
  end
end
