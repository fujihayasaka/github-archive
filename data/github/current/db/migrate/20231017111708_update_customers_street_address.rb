class UpdateCustomersStreetAddress < ActiveRecord::Migration[7.2]
  def up
    change_column :customers, :street_address, "varchar(128)", null: true
  end

  def down
    change_column :customers, :street_address, "varchar(100)", null: true
  end
end
