# typed: true

class AddExtrasToBillingTransactionLineItems < ActiveRecord::Migration[7.1]
  def change
    add_column :billing_transaction_line_items, :extras, :json, null: true
  end
end
