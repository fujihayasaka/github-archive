# typed: true

class AddSalesManagedTrialToBusinesses < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :businesses, :sales_managed_trial, :boolean, null: false, default: false
  end
end
