# typed: true
# frozen_string_literal: true

class CreateElmExporterAuthentications < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    create_table :elm_exporter_authentications, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :migration_id, limit: 36, null: false
      t.string :authentication_type, limit: 100, null: false
      t.string :system_pat_name, limit: 100, null: true
      t.datetime :created_at, precision: 6, null: false, default: -> { "CURRENT_TIMESTAMP(6)" }

      t.index :migration_id, name: "idx_elm_exporter_authentications_migration_id"
      t.index :authentication_type, name: "idx_elm_exporter_authentications_type"
    end
  end
end
