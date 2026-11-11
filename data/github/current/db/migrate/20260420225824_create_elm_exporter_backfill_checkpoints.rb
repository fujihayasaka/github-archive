# typed: true
# frozen_string_literal: true

class CreateElmExporterBackfillCheckpoints < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    create_table :elm_exporter_backfill_checkpoints, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :migration_id, limit: 36, null: false
      t.string :resource_type, limit: 100, null: false
      t.datetime :completed_at, precision: 6, null: false, default: -> { "CURRENT_TIMESTAMP(6)" }

      t.index [:migration_id, :resource_type], unique: true, name: "idx_elm_exporter_backfill_checkpoints_migration_id_resource"
    end
  end
end
