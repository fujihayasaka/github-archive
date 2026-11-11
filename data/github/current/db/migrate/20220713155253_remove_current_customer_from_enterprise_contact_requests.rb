# typed: true

class RemoveCurrentCustomerFromEnterpriseContactRequests < ActiveRecord::Migration[7.1]
  def up
    remove_column :enterprise_contact_requests, :current_customer
  end

  def down
    add_column :enterprise_contact_requests, :current_customer, :boolean, null: false, default: false
  end
end
