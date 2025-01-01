# typed: true
class AddDeletedToActionPackagesMetadata < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table :action_packages_metadata, bulk: true do |t|
      t.remove_index [:action_package_name, :major_version, :is_latest], name: "index_action_packages_metadata_package_name_major_version_latest"

      t.boolean :deleted, null: false, default: false
      t.column :deleted_at, "DATETIME(6)", null: true, default: nil
      t.index [:action_package_name, :major_version, :is_latest, :deleted], name: "index_action_packages_metadata_name_major_version_latest_deleted"
    end
  end
end
