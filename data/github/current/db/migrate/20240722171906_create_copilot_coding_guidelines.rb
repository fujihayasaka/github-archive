class CreateCopilotCodingGuidelines < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_coding_guidelines, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :repository_id, :bigint, unsigned: true, null: false, index: true
      t.boolean :enabled, null: false, default: false, index: true
      t.string :name, null: false, limit: 200
      t.text :description, null: false
      t.text :example_code_violations
      t.timestamps
    end
  end
end
