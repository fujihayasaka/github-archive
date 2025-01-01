class AddFirstNameLastNameToEnterpriseContactRequests < ActiveRecord::Migration[7.2]
  def change
    change_table :enterprise_contact_requests, bulk: true do |t|
      t.string :first_name, null: true, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.string :last_name, null: true, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
    end
  end
end
