# typed: true
class AddAttributesToActionPackagesMetadata < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table :action_packages_metadata, bulk: true do |t|
      t.column :release_tag, "varbinary(1024)", null: false, default: ""
      t.integer :major_version, unsigned: true, null: false, default: 0
      t.boolean :is_latest, null: false, default: false

      t.index [:action_package_name, :major_version, :is_latest], name: "index_action_packages_metadata_package_name_major_version_latest"
    end
  end
end
