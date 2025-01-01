# typed: true

class AddDigestToReleaseAssets < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::AssetObjects)

  def up
    change_table :release_assets, bulk: true do |t|
      t.column :digest, :string, limit: 256, null: true

      # Upgrade integer primary and foreign key columns to BIGINT
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
      t.change :release_id, :bigint, unsigned: true
      t.change :uploader_id, :bigint, unsigned: true
      t.change :storage_blob_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :release_assets, bulk: true do |t|
      t.remove :digest

      t.change :id, :int, unsigned: false
      t.change :repository_id, :int, unsigned: false
      t.change :release_id, :int, unsigned: false
      t.change :uploader_id, :int, unsigned: false
      t.change :storage_blob_id, :int, unsigned: false
    end
  end
end
