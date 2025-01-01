# typed: true

class AddIndexForUniqueNumberIdentifierOnPaymentMethods < ActiveRecord::Migration[7.1]
  def up
    change_table :payment_methods, bulk: true do |t|
      t.index :unique_number_identifier, name: "index_on_unique_number_identifier", unique: false

      t.change :id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
      t.change :customer_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :payment_methods, bulk: true do |t|
      t.remove_index name: "index_on_unique_number_identifier"

      t.change :id, :int, unsigned: false
      t.change :user_id, :int, unsigned: false
      t.change :customer_id, :int, unsigned: false
    end
  end
end
