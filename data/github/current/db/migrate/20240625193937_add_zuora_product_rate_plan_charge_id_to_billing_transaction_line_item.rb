class AddZuoraProductRatePlanChargeIdToBillingTransactionLineItem < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :billing_transaction_line_items, bulk: true do |t|
      t.string :zuora_product_rate_plan_charge_id, limit: 32
      t.index [:zuora_product_rate_plan_charge_id, :billing_transaction_id]
    end
  end
end
