# typed: true

class DropBraintreeIdFromPlanSubscription < ActiveRecord::Migration[7.1]
  self.use_connection_class(Billing::PlanSubscription)

  def up
    change_table :plan_subscriptions, bulk: true do |t|
      t.remove :braintree_id
      t.remove_index :braintree_id
    end
  end

  def down
    change_table :plan_subscriptions, bulk: true do |t|
      t.string :braintree_id
      t.index :braintree_id
    end
  end
end
