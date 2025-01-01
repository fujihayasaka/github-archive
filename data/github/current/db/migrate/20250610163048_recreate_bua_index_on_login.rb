# typed: true
# frozen_string_literal: true

class RecreateBuaIndexOnLogin < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_index :business_user_accounts, [:business_id, :user_id, :login], name: :idx_business_user_accounts_on_business_id_user_id_login
  end
end
