class DropMigratableResourcesTable < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    drop_table :migratable_resources, id: :bigint, charset: "utf8mb3" do |t|
      t.string :guid, limit: 36, null: false
      t.bigint :model_id
      t.text :source_url, null: false
      t.text :target_url
      t.integer :state, default: 0
      t.integer :migration_id
      t.string :model_type, limit: 64, null: false
      t.text :warning

      t.index [:guid, :source_url], length: { source_url: 511 }, unique: true
      t.index [:guid, :state, :model_type]
      t.index [:guid, :model_type]
      t.index [:guid, :warning], length: { warning: 1 }
    end
  end
end
