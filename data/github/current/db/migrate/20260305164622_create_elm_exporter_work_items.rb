# typed: true
# frozen_string_literal: true

class CreateElmExporterWorkItems < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    create_table :elm_exporter_work_items, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :migration_id, limit: 36, null: false
      t.string :status, limit: 100, null: false
      t.string :component, limit: 32, null: false
      t.string :process_id, limit: 128
      t.datetime :lease_expires_at, precision: 6
      t.string :work_item_type, limit: 32, null: false
      t.json :work_item_data, null: false
      t.timestamps
    end
  end
end
