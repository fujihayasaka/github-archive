# typed: true

class CreateModelsPrompts < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def change
    create_table :models_prompts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :path, null: false
      t.string :name, null: true
      t.string :model, null: true
      t.string :description, null: true
      t.unsigned_bigint :owner_id, null: false
      t.unsigned_bigint :repository_id, null: false
      t.timestamps

      t.index [:owner_id, :repository_id]
    end
  end
end
