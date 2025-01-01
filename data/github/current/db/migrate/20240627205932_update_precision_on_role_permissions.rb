class UpdatePrecisionOnRolePermissions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Iam)
  def up
    change_table :role_permissions, bulk: true do |t|
      t.change :created_at, :datetime, precision: 6, null: false
      t.change :updated_at, :datetime, precision: 6, null: false
      # Change id references to bigint unsigned
      t.change :id, :bigint, null: false, unsigned: true
      t.change :role_id, :bigint, null: false, unsigned: true
      t.change :fine_grained_permission_id, :bigint, null: false, unsigned: true
    end
  end

  def down
    change_table :role_permissions, bulk: true do |t|
      t.change :created_at, :datetime, precision: 0, null: false
      t.change :updated_at, :datetime, precision: 0, null: false
      # rollback bigint unsigned change
      t.change :id, :int, null: false
      t.change :role_id, :int, null: false
      t.change :fine_grained_permission_id, :int, null: false
    end
  end
end
