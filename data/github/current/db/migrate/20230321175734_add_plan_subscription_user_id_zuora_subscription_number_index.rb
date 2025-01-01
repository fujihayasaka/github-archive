# typed: true
class AddPlanSubscriptionUserIdZuoraSubscriptionNumberIndex < ActiveRecord::Migration[7.1]
  def change
    # Name as to be customized because the default is too long
    add_index :plan_subscriptions,
      %i[user_id zuora_subscription_number],
      unique: true,
      name: "index_plan_subscriptions_on_user_id_zuora_subscription_number"
  end
end
