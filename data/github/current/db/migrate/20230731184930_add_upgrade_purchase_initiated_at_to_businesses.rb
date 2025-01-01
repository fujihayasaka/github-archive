# typed: true
class AddUpgradePurchaseInitiatedAtToBusinesses < ActiveRecord::Migration[7.1]
  def change
    change_table :businesses, bulk: true do |t|
      t.column :upgrade_purchase_initiated_at, :datetime, precision: 6, null: true, after: :upgraded_at
      t.index :upgrade_purchase_initiated_at
    end
  end
end
