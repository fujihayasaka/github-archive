# typed: true
# frozen_string_literal: true

class MakeBusinessUserAccountsLoginIndexInvisible < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    disable_index :business_user_accounts, :index_business_user_accounts_on_login
  end
end
