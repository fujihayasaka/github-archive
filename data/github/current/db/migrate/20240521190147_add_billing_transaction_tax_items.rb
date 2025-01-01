# typed: true
# frozen_string_literal: true

class AddBillingTransactionTaxItems < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    create_table(:billing_transaction_tax_items, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci") do |t|
      t.bigint  :billing_transaction_line_item_id, unsigned: true, null: false
      t.integer :amount_in_cents, null: false, default: 0
      t.integer :exempt_amount_in_cents, null: false, default: 0
      t.string  :country, limit: 3, null: false
      t.string  :name, null: false, limit: 128
      t.string  :jurisdiction, null: false, limit: 32
      t.string  :location_code, limit: 32
      t.string  :tax_code, limit: 32
      t.string  :tax_code_description
      t.date    :tax_date, null: false
      t.decimal :tax_rate, precision: 5, scale: 4, null: false
      t.string  :tax_rate_description
      t.string  :tax_rate_type, null: false, limit: 10
      t.string  :source_id, null: false, limit: 36
      t.string  :source_name, null: false, limit: 5

      t.index :billing_transaction_line_item_id
      t.index [:source_id, :source_name], unique: true
    end
  end
end
