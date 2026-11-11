# typed: true

class CreateCopilotCustomModelCapabilities < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_custom_model_capabilities, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :copilot_custom_model_id, unsigned: true, null: false
      t.integer :max_output_tokens, unsigned: true, null: false, default: 0
      t.integer :max_input_tokens, unsigned: true, null: false, default: 0
      t.boolean :tool_calling, null: false, default: false
      t.boolean :vision, null: false, default: false
      t.boolean :thinking, null: false, default: false
      t.timestamps

      t.index :copilot_custom_model_id, unique: true
    end
  end
end
