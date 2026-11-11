# typed: true

class AddModelRegistryCacheToCopilot < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :model_registry_cache, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :model_key, null: false, index: true
      t.string :name, null: false
      t.json :description
      t.string :plans
      t.string :feature_flag
      t.boolean :internal, null: false, default: true
      t.timestamps
    end
  end
end
