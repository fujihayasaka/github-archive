# typed: true
# frozen_string_literal: true

class AddStripeConnectAccountsVerificationStatus < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_table :stripe_connect_accounts, bulk: true do |t|
      t.integer :verification_status, null: false, default: 0, after: :verified
      t.index [:payable_type, :verification_status, :country],
        name: "idx_stripe_connect_accounts_on_payable_type_verif_status_country"
    end
  end
end
