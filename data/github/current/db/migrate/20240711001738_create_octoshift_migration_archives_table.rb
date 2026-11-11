class CreateOctoshiftMigrationArchivesTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    create_table :octoshift_migration_archives, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :organization_id, :bigint, unsigned: true
      t.column :content_type, :string
      t.column :size, :integer
      t.column :state, :integer, null: false, default: 0
      t.column :name, :string
      t.column :uploader_id, :bigint, unsigned: true
      t.column :storage_blob_id, :bigint, unsigned: true
      t.column :oid, :string, limit: 64
      t.column :storage_provider, :string, limit: 30

      t.index :organization_id
      t.index :uploader_id
      t.index :storage_blob_id

      t.timestamps
    end
  end
end
