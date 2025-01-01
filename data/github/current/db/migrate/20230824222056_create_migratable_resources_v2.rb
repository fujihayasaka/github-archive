class CreateMigratableResourcesV2 < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    create_table :migratable_resources_v2, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :guid, limit: 36, null: false
      t.bigint :model_id, unsigned: true
      t.text :source_url, null: false
      t.text :target_url
      t.integer :state, default: 0
      t.bigint :migration_id, unsigned: true
      t.string :model_type, limit: 64, null: false
      t.text :warning

      t.timestamps

      t.index [:guid, :source_url], length: { source_url: 511 }, unique: true
      t.index [:guid, :state, :model_type]
      t.index [:guid, :model_type]
      t.index [:guid, :warning], length: { warning: 1 }
    end
  end
end
