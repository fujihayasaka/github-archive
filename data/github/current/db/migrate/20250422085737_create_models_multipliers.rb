# typed: true
# frozen_string_literal: true

class CreateModelsMultipliers < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def change
    create_table :models_multipliers, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :models_slug, limit: 80, null: false
      t.column :input, :decimal, precision: 10, scale: 5, null: false
      t.column :cached_input, :decimal, precision: 10, scale: 5, null: true
      t.column :output, :decimal, precision: 10, scale: 5, null: false
      t.timestamps

      t.index :models_slug, unique: true
    end
  end
end
