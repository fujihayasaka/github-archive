# typed: true
# frozen_string_literal: true

class AddAccountOwnerHandleToSalesforceAccounts < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :salesforce_accounts, :account_owner_handle, :string, limit: 40
  end
end
