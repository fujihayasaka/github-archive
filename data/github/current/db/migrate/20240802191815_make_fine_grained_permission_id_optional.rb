class MakeFineGrainedPermissionIdOptional < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Iam)
  def up
    change_column :role_permissions, :fine_grained_permission_id, :bigint, null: true, unsigned: true
  end

  def down
    change_column :role_permissions, :fine_grained_permission_id, :bigint, null: false, unsigned: true
  end
end
