# typed: true
# frozen_string_literal: true

class DropStripeConnectAccountsPayableTypeAndPayableId < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def up
    change_table :stripe_connect_accounts, bulk: true do |t|
      t.remove_index name: "idx_stripe_connect_accounts_on_payable_type_and_payouts_enabled"
      t.remove_index name: "idx_stripe_connect_accounts_on_payable_type_and_billing_country"
      t.remove_index name: "index_stripe_connect_accounts_on_payable_id_and_payable_type"
      t.remove_index name: "idx_stripe_connect_accounts_on_payable_type_verif_status_country"

      t.remove :payable_id
      t.remove :payable_type
    end
  end

  def down
    change_table :stripe_connect_accounts, bulk: true do |t|
      t.column :payable_type, "varchar(32)", default: "SponsorsListing", after: :id, null: false
      t.bigint :payable_id, null: false, unsigned: true, default: 0, after: :payable_type

      t.index [:payable_type, :payouts_enabled],
        name: "idx_stripe_connect_accounts_on_payable_type_and_payouts_enabled"
      t.index [:payable_type, :billing_country],
        name: "idx_stripe_connect_accounts_on_payable_type_and_billing_country"
      t.index [:payable_id, :payable_type], name: "index_stripe_connect_accounts_on_payable_id_and_payable_type"
      t.index [:payable_type, :verification_status, :country],
        name: "idx_stripe_connect_accounts_on_payable_type_verif_status_country"
    end
  end
end
