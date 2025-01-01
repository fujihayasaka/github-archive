# typed: true
class RemovePaypalIdAndTransactionTypeIndexOnPayoutsLedgerEntry < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_table :billing_payouts_ledger_entries, bulk: true do |t|
      t.remove_index name: :idx_billing_payouts_ledger_entries_on_paypal_id_and_txn_type
    end
  end
end
