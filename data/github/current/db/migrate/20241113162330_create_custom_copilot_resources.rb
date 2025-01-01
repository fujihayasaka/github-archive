# typed: true

class CreateCustomCopilotResources < ActiveRecord::Migration[8.1]

  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :custom_copilot_resources, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :custom_copilot_id, unsigned: true, null: false
      t.integer :resource_type, null: false
      t.json :metadata, null: false
      t.timestamps

      t.index [:custom_copilot_id], name: "index_custom_copilot_resources_on_custom_copilot_id"
    end
  end
end
