# typed: true

class AddBillOnTrialExpirationToProductUUID < ActiveRecord::Migration[7.1]
  def up
    add_column :product_uuids, :bill_on_trial_expiration, :boolean, null: false, default: true
  end

  def down
    remove_column :product_uuids, :bill_on_trial_expiration, :boolean, null: false, default: true
  end
end
