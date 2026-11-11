# typed: true

class CreateRestorableWatchedRepositoryThreads < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::Restorables

  def change
    create_table :restorable_watched_repository_threads, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.timestamps

      t.bigint :restorable_id, unsigned: true, null: false, index: true
      t.bigint :user_id, unsigned: true, null: false
      t.boolean :ignored, null: false
      t.string :reason, limit: 40
      t.string :thread_key, limit: 80, null: false
    end
  end
end
