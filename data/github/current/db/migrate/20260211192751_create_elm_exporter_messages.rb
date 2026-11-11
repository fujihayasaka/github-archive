# typed: true
# frozen_string_literal: true

class CreateElmExporterMessages < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    create_table :elm_exporter_messages, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :migration_id, limit: 36, null: false
      t.string :message_type, limit: 10, null: false
      t.text :message, null: false
      t.datetime :created_at, precision: 6, null: false, default: -> { "CURRENT_TIMESTAMP(6)" }

      t.index :migration_id, name: "idx_elm_exporter_messages_migration_id"
      t.index :message_type, name: "idx_elm_exporter_messages_type"
    end
  end
end
