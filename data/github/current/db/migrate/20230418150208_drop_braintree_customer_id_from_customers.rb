# typed: true
class DropBraintreeCustomerIdFromCustomers < ActiveRecord::Migration[7.1]
  def change
    remove_column :customers, :braintree_customer_id, :string, limit: 30
  end
end
