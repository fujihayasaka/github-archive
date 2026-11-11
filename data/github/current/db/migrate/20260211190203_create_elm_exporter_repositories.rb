# typed: true
# frozen_string_literal: true

class CreateElmExporterRepositories < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    create_table :elm_exporter_repositories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :migration_id, limit: 36, null: false
      t.string :source_git_url, limit: 366, null: false # rubocop:disable GitHub/URLColumnsMustBeText
      t.string :target_git_url, limit: 366, null: false # rubocop:disable GitHub/URLColumnsMustBeText
      t.string :status, limit: 100, null: false
      t.datetime :created_at, precision: 6, null: false, default: -> { "CURRENT_TIMESTAMP(6)" }

      t.index :status, name: "idx_elm_exporter_repositories_status"
      t.index [:migration_id, :source_git_url, :target_git_url], unique: true, name: "idx_elm_exporter_repositories_urls"
    end
  end
end
