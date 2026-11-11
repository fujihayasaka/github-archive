class UpdatePrecisionOnRoles < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Iam)
  def up
    change_table :roles, bulk: true do |t|
      t.change :created_at, :datetime, precision: 6, null: false
      t.change :updated_at, :datetime, precision: 6, null: false
    end
  end

  def down
    change_table :roles, bulk: true do |t|
      t.change :created_at, :datetime, precision: 0, null: false
      t.change :updated_at, :datetime, precision: 0, null: false
    end
  end

end
