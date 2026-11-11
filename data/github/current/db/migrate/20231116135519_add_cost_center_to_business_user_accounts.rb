class AddCostCenterToBusinessUserAccounts < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_column :business_user_accounts, :cost_center, :string, null: true, limit: 36
  end
end
