class CreateZuoraRatePlanCharges < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  def change
    create_table :zuora_rate_plan_charges, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :plan_subscription_id, unsigned: true, index: true, null: false
      t.string :product_rate_plan_charge_id, index: true, null: false, limit: 32
      t.json   :payload, null: false

      t.timestamps
    end
  end
end
