# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
# typed: true
# frozen_string_literal: true

class CreateElmExporterMigrations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    create_table :elm_exporter_migrations, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :id, limit: 36, null: false, primary_key: true
      t.string :status, limit: 100, null: false
      t.string :source_organization_login, limit: 100, null: false
      t.string :source_repository_name, limit: 100, null: false
      t.string :target_organization_login, limit: 100, null: false
      t.string :target_repository_name, limit: 100, null: false
      t.string :target_visibility, limit: 10, null: false, default: "internal"
      t.string :target_api_endpoint, limit: 255, null: false
      t.bigint :target_migration_id, unsigned: true
      t.bigint :source_migration_id, unsigned: true
      t.datetime :backfill_completed_at, precision: 6, null: true
      t.datetime :cutover_started_at, precision: 6, null: true
      t.datetime :repository_locked_at, precision: 6, null: true
      t.datetime :workers_paused_at, precision: 6, null: true
      t.datetime :created_at, precision: 6, null: false, default: -> { "CURRENT_TIMESTAMP(6)" }
      t.datetime :started_at, precision: 6, null: true
      t.datetime :completed_at, precision: 6, null: true
      t.datetime :expires_at, precision: 6, null: true

      t.index :status, name: "idx_elm_exporter_migrations_status"
      t.index :created_at, name: "idx_elm_exporter_migrations_created_at"
    end
  end
end
