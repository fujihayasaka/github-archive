# typed: true
# frozen_string_literal: true

class CreateMigrationExportBatches < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    create_table :migration_export_batches, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :migration_id, unsigned: true, null: false
      t.string :model_type, limit: 64, null: false
      t.integer :type, null: false, default: 0
      t.integer :state, null: false, default: 0
      t.json :model_ids, null: false
      t.integer :success_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.datetime :queued_at, precision: 6, null: true
      t.datetime :started_at, precision: 6, null: true
      t.datetime :completed_at, precision: 6, null: true
      t.bigint :migration_file_id, unsigned: true, null: true
      t.json :critical_error
      t.json :processing_errors

      t.timestamps

      t.index [:migration_id, :state, :type], name: "index_migration_export_batches_on_migration_id_state_batch_type"
    end
  end
end
