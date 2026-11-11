# typed: true

class CreateRestorableCustomWatchedRepositories < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::Restorables

  def change
    create_table :restorable_custom_watched_repositories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.timestamps

      t.bigint :restorable_id, unsigned: true, null: false, index: true
      t.bigint :user_id, unsigned: true, null: false
      t.string :thread_type, limit: 64, null: false
      t.datetime :original_created_at, null: false, precision: 6
    end
  end
end
