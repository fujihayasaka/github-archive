# typed: true

class AddColumnsToCustomModelCapabilities < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_custom_model_capabilities, bulk: true do |t|
      t.column :endpoint_type, :tinyint, unsigned: true, null: false, default: 0

      t.boolean :streaming, null: false, default: false

      t.integer :max_context_window, unsigned: true, null: false, default: 0
    end
  end
end
