# typed: true
# frozen_string_literal: true

class DropBusinessUserAccountsLoginIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    remove_index :business_user_accounts, name: :index_business_user_accounts_on_login
  end

  def down
    add_index :business_user_accounts, :login, name: "index_business_user_accounts_on_login", enabled: false
  end
end
