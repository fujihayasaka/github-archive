# typed: true

class CreateCopilotSharedThreads < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::CopilotPLG

  def change
    create_table :copilot_shared_threads, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :slug, limit: 36, null: false
      t.string :thread_id, limit: 36, null: false
      t.datetime :shared_at, precision: 6, null: false
      t.timestamps

      t.index :slug, unique: true
      t.index :thread_id, unique: true
    end
  end
end
