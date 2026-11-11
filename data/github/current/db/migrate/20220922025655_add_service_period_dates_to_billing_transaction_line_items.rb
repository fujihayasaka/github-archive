# typed: true

class AddServicePeriodDatesToBillingTransactionLineItems < ActiveRecord::Migration[7.1]
  def up
    change_table :billing_transaction_line_items, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, auto_increment: true, null: false
      t.change :billing_transaction_id, :bigint, unsigned: true, null: false
      t.change :subscribable_id, :bigint, unsigned: true
      t.date :service_start_date
      t.date :service_end_date
    end
  end

  def down
    change_table :billing_transaction_line_items, bulk: true do |t|
      t.change :id, :int, auto_increment: true, null: false
      t.change :billing_transaction_id, :int, null: false
      t.change :subscribable_id, :int
      t.remove :service_start_date, :service_end_date
    end
  end
end
