# typed: true

class AddVisibilityToCustomCopilots < ActiveRecord::Migration[8.1]

  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :custom_copilots, bulk: true do |t|
      t.integer :visibility, null: false, default: 0

      t.index [:owner_id, :owner_type, :visibility], name: "index_custom_copilot_on_owner_id_and_owner_type_and_visibility"
    end
  end
end
