class AddFieldsForFilteredMembersToBusinessUserAccounts < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :business_user_accounts, bulk: true do |t|
      t.column :two_factor_status, :tinyint, unsigned: true, null: true
      t.column :profile_name, "varchar(255)", null: true
      t.text   :verified_emails, null: true
    end
  end

  def down
    change_table :business_user_accounts, bulk: true do |t|
      t.remove :two_factor_status
      t.remove :profile_name
      t.remove :verified_emails
    end
  end
end
