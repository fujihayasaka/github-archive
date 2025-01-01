class AddCustomerIdIndexToBusinesses < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :businesses, bulk: true do |t|
      t.index [:customer_id], unique: false, name: "index_businesses_on_customer_id"
    end
  end

  def down
    change_table :businesses, bulk: true do |t|
      t.remove_index name: "index_businesses_on_customer_id"
    end
  end
end
