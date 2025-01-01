# typed: true

class AddBaseRoleToCustomCopilots < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :custom_copilots, bulk: true do |t|
      t.integer :base_role, null: false, default: 0

      t.index [:owner_id, :owner_type, :base_role], name: "index_custom_copilot_on_owner_id_and_owner_type_and_base_role"
    end
  end
end
