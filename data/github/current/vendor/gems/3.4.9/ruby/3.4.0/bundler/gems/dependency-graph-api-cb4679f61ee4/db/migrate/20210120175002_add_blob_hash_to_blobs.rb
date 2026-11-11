class AddBlobHashToBlobs < ActiveRecord::Migration[6.0]
  def change
    add_column :dg_snapshot_blobs, :blob_hash, :string, limit: 128
    add_index :dg_snapshot_blobs, [:blob_hash], name: :index_dg_snapshot_blobs_on_hash

    add_index :dg_snapshots, [:repository_id, :source, :sha], name: "index_dg_snapshots_on_repository_id_source_and_sha"
  end
end
