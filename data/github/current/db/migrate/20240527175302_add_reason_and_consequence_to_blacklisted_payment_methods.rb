# rubocop:disable Naming/InclusiveLanguage the db table is named BlacklistedPaymentMethods :(
# TODO: the table name will have to be changed to BlocklistedPaymentMethods
class AddReasonAndConsequenceToBlacklistedPaymentMethods < ActiveRecord::Migration[7.2]
  def up
    change_table :blacklisted_payment_methods, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
      t.column :reason, :text, null: true
      t.column :consequence, "enum('suspended', 'billing_locked')", null: false, default: "suspended"
    end
  end

  def down
    change_table :blacklisted_payment_methods, bulk: true do |t|
      t.change :id, :integer, auto_increment: true, null: false
      t.change :user_id, :integer, null: false
      t.remove :reason
      t.remove :consequence
    end
  end
end

# rubocop:enable Naming/InclusiveLanguage
