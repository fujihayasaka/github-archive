# typed: true

class CreateModelsBlocks < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def change
    create_table :models_blocks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :actor_id, :bigint, unsigned: true, null: false
      t.column :user_id, :bigint, unsigned: true, null: false
      t.string :reason, null: false, limit: 1024
      t.column :state, :tinyint, unsigned: true, default: 0, null: false
      t.timestamps

      t.index :user_id
    end
  end
end
