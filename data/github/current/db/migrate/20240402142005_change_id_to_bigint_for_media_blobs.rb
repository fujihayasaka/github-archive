class ChangeIdToBigintForMediaBlobs < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Assets)

  def up
    change_table(:media_blobs, bulk: true) do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :asset_id, :bigint, unsigned: true, default: nil
      t.change :repository_network_id, :bigint, unsigned: true, default: nil
      t.change :originating_repository_id, :bigint, unsigned: true, default: nil
      t.change :pusher_id, :bigint, unsigned: true, default: nil
      t.change :storage_blob_id, :bigint, unsigned: true, default: nil
    end
  end

  def down
    change_table(:media_blobs, bulk: true) do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :asset_id, :int, default: nil
      t.change :repository_network_id, :int, default: nil
      t.change :originating_repository_id, :int, default: nil
      t.change :pusher_id, :int, default: nil
      t.change :storage_blob_id, :int, default: nil
    end
  end
end
