# typed: true

class AddActionPackagesMetadata < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    create_table :action_packages_metadata, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.column :action_package_name, :string, limit: 255, null: false
      t.column :tag_name, "varbinary(1024)", null: false
      t.column :package_metadata, :json, null: true
      t.column :state, :tinyint, unsigned: true, null: false
      t.column :error_message, :text, null: true
      t.timestamps

      t.index [:action_package_name, :tag_name], name: "index_action_packages_metadata_action_package_name_tag", unique: true
    end
  end
end
