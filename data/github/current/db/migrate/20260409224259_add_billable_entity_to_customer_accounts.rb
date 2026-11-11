# typed: true
# frozen_string_literal: true

class AddBillableEntityToCustomerAccounts < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :customer_accounts, bulk: true do |t|
      t.change :user_id, :bigint, unsigned: true, null: true
      t.string :billable_entity_type, null: true
      t.bigint :billable_entity_id, unsigned: true, null: true
      t.index [:billable_entity_id, :billable_entity_type, :purpose], unique: true, name: "idx_customer_accounts_on_billable_entity_and_purpose" # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn -- billable_entity columns are new in this migration
    end
  end

  def down
    change_table :customer_accounts, bulk: true do |t|
      t.change :user_id, :bigint, unsigned: true, null: false
      t.remove_index name: "idx_customer_accounts_on_billable_entity_and_purpose"
      t.remove :billable_entity_type
      t.remove :billable_entity_id
    end
  end
end
