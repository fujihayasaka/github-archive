class CreateSnapshotTables < ActiveRecord::Migration[6.0]
  def change
    create_table :dg_snapshot_blobs, id: false, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.bigint :id, primary_key: true, null: false, auto_increment: true, limit: 20, unsigned: true
      t.column :blob, :json, null: false
      t.integer :blob_size_bytes, null: false
      t.datetime :created_at, null: false
    end

    create_table :dg_snapshots, id: false, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.bigint :id, primary_key: true, null: false, auto_increment: true, limit: 20, unsigned: true
      t.integer :repository_id, null: false
      t.bigint :snapshot_blob_id, null: false, unsigned: true
      t.string :source, null: true, limit: 255
      t.string :sha, null: false, limit: 64
      t.column :metadata, :json, null: true
      t.datetime :created_at, null: false
    end

    add_index :dg_snapshots, [:repository_id, :sha], name: "index_dg_snapshots_on_repository_id_and_sha"
  end
end
