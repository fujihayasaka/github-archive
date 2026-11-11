class AddUpdatedByIdToCustomInstructions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_custom_instructions, bulk: true do |t|
      t.column :updated_by_id, :bigint, unsigned: true, null: true
    end
  end
end
