# typed: true

class AddUsingAdvancedSecurityToEnterpriseInstallationUserAccounts < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_column :enterprise_installation_user_accounts, :using_advanced_security, :boolean, default: nil, null: true

    # upgrade related columns as part of fan out work
    change_table :enterprise_installation_user_accounts, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :enterprise_installation_id, :bigint, unsigned: true
      t.change :remote_user_id, :bigint, unsigned: true
      t.change :business_user_account_id, :bigint, unsigned: true
    end
  end
end
