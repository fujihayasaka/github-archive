# typed: true
class CreateSearchCustomScopes < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    create_table :search_custom_scopes, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.belongs_to :user, null: false, unsigned: true, index: true
      t.string :name, limit: 50, null: false
      t.string :query, limit: 500, null: false
      t.integer :color, default: 0

      t.timestamps
    end
  end
end
