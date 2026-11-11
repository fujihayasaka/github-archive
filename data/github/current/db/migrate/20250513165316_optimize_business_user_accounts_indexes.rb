# typed: true
# frozen_string_literal: true

class OptimizeBusinessUserAccountsIndexes < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :business_user_accounts, bulk: true do |t|
      t.remove_index name: :index_business_user_accounts_on_business_id_user_id_login
      t.index :login, name: :index_business_user_accounts_on_login
    end
  end

  def down
    change_table :business_user_accounts, bulk: true do |t|
      t.remove_index name: :index_business_user_accounts_on_login
      t.index [:business_id, :user_id, :login], name: :index_business_user_accounts_on_business_id_user_id_login
    end
  end
end
