class BusinessUserAccountsAddSpammy < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_column :business_user_accounts, :spammy, "tinyint(1)", null: false, default: 0
  end
end
