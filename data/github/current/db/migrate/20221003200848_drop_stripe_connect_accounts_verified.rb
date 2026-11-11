# typed: true
# frozen_string_literal: true

class DropStripeConnectAccountsVerified < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def up
    change_table :stripe_connect_accounts, bulk: true do |t|
      t.remove :verified
      t.remove_index name: "idx_stripe_connect_accounts_payable_type_verified_country"
    end
  end

  def down
    change_table :stripe_connect_accounts, bulk: true do |t|
      t.boolean :verified, null: false, default: false, after: :country
      t.index [:payable_type, :verified, :country],
        name: "idx_stripe_connect_accounts_payable_type_verified_country"
    end
  end
end
