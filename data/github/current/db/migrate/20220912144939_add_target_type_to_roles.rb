# typed: true
class AddTargetTypeToRoles < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Iam)

  def change
    change_table :roles, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :owner_id, :bigint, unsigned: true
      t.change :base_role_id, :bigint, unsigned: true

      t.column :target_type, :string, limit: 60, null: true
    end
  end
end
