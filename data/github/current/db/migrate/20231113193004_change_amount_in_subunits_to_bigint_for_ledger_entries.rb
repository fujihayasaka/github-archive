class ChangeAmountInSubunitsToBigintForLedgerEntries < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def up
    change_column :billing_payouts_ledger_entries, :amount_in_subunits, :bigint, default: 0, null: false
  end

  def down
    change_column :billing_payouts_ledger_entries, :amount_in_subunits, :int, default: 0, null: false
  end
end
