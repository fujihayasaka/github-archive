class AddPlanSubscriptionTypeToZuoraRatePlanCharges < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  def change
    change_table :zuora_rate_plan_charges, bulk: true do |t|
      t.string :plan_subscription_type, limit: 35
      t.remove_index [:plan_subscription_id]
      t.index [:plan_subscription_id, :plan_subscription_type]
    end
  end
end
