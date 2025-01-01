# typed: true

class CreateCustomCopilots < ActiveRecord::Migration[8.1]

  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :custom_copilots, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :name, limit: 255, null: false
      t.text :description, null: true
      t.text :icon_url, null: true
      t.references :owner, polymorphic: true, null: false
      t.timestamps
    end
  end
end
