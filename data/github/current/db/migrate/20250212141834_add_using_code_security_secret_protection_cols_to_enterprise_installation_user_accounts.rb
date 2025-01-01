# typed: true

class AddUsingCodeSecuritySecretProtectionColsToEnterpriseInstallationUserAccounts < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :enterprise_installation_user_accounts, bulk: true do |t|
      t.column :using_code_security, :boolean, default: nil, null: true, after: :using_advanced_security
      t.column :using_secret_protection, :boolean, default: nil, null: true, after: :using_code_security
    end
  end

  def down
    change_table :enterprise_installation_user_accounts, bulk: true do |t|
      t.remove :using_secret_protection
      t.remove :using_code_security
    end
  end
end
