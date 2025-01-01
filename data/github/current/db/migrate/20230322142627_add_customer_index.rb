# typed: true
class AddCustomerIndex < ActiveRecord::Migration[7.1]
  def change
    add_index :customers, :parent_customer_id, if_not_exists: true
  end
end
