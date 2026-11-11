class AddCopilotCustomInstructions < ActiveRecord::Migration[7.2]

  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_custom_instructions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :owner_id, :bigint, unsigned: true, null: false
      t.column :owner_type, :string, null: false, limit: 20
      t.text :prompt
      t.index [:owner_id, :owner_type], name: "index_copilot_custom_instructions_on_owner_id_and_owner_type", unique: true
      t.timestamps
    end
  end
end
