# typed: true

class AddAssetTypeToAttachments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::AssetObjects)
  def change
    change_table :attachments, bulk: true do |t|
      t.column :asset_type, "enum('UserAsset', 'RepositoryFile')", null: false, default: "UserAsset"
      t.remove_index name: "by_asset"
      t.index [:asset_id, :asset_type, :attachable_id, :attachable_type], unique: true, name: "by_asset"
      t.remove_index name: "by_attachable"
      t.index [:attachable_id, :attachable_type, :asset_type], name: "by_attachable_and_asset_type"
    end
  end
end
