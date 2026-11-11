# typed: true

class CreateRestorableVisibilityChangedRepositories < ActiveRecord::Migration[8.1]
  # mysql1
  use_connection_class ApplicationRecord::Domain::Restorables

  def change
    create_table :restorable_visibility_changed_repositories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.timestamps

      t.bigint :restorable_id, unsigned: true, null: false, index: true
      t.bigint :repository_id, unsigned: true, null: false

      t.index [:repository_id, :restorable_id], unique: true
    end
  end
end
