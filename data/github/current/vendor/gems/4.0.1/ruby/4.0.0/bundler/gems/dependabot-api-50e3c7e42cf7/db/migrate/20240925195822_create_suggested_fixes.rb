# frozen_string_literal: true

class CreateSuggestedFixes < ActiveRecord::Migration[7.0]
  def change
    create_table :suggested_fixes, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.references :autofix_suggestion_job, unsigned: true, null: false
      t.text :description, null: true
      t.string :ai_version, null: true, limit: 50
      t.string :ai_model, null: true, limit: 50
      t.json :dependency_metadata, null: true
      t.integer :review_status, default: 0
      t.timestamps
    end
  end
end
