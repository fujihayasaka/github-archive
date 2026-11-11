# typed: true
# frozen_string_literal: true

class RemoveRedundantBusinessUserAccountIdIndexFromEiua < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    remove_index :enterprise_installation_user_accounts,
      name: :idx_ent_installation_user_accounts_on_business_user_account_id
  end

  def down
    add_index :enterprise_installation_user_accounts,
      :business_user_account_id,
      name: :idx_ent_installation_user_accounts_on_business_user_account_id
  end
end
