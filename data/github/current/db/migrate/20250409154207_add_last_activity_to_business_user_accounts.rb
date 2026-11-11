# typed: true
# frozen_string_literal: true

class AddLastActivityToBusinessUserAccounts < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table :business_user_accounts, bulk: true do |t|
      t.column :last_business_activity_at, :timestamp, null: true
      t.index [:business_id, :last_business_activity_at], name: "index_business_user_accounts_on_business_id_last_activity_at"
    end
  end
end
