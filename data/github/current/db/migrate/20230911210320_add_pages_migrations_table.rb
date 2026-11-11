class AddPagesMigrationsTable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :pages_migrations,  id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :page_id, unsigned: true, null: false
      t.bigint :page_deployment_id, unsigned: true, null: false
      t.json :manifest
      t.datetime :created_at, precision: 6, null: true
      t.datetime :started_at, precision: 6, null: true
      t.datetime :updated_at, precision: 6, null: true
      t.integer :status, limit: 1, unsigned: true, null: false, default: 0, comment: "Current state of migration. See enum in PageMigration model"
    end

    add_index :pages_migrations, [:page_id, :page_deployment_id], name: :index_page_id_page_deployment_id

  end
end
