# typed: true
# frozen_string_literal: true

class UpdateSalesforceAccountIdIndexOnBusinesses < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :businesses, bulk: true do |t|
      t.remove_index :salesforce_account_id
      t.index :salesforce_account_id, unique: true # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
    end
  end

  def down
    change_table :businesses, bulk: true do |t|
      t.remove_index :salesforce_account_id
      t.index :salesforce_account_id
    end
  end
end
