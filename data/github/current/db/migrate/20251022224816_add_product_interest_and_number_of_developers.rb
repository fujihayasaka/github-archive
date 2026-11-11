# typed: true

class AddProductInterestAndNumberOfDevelopers < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Site)

  def change
    change_table :enterprise_contact_requests, bulk: true do |t|
      t.column :product_interest, :string, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.column :number_of_developers, :string, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
    end
  end
end
