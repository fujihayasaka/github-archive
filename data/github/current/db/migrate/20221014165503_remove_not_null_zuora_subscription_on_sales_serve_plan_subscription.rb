# typed: false

class RemoveNotNullZuoraSubscriptionOnSalesServePlanSubscription < ActiveRecord::Migration[7.1]
  self.use_connection_class ApplicationRecord::Billing

  def self.up
    change_table :billing_sales_serve_plan_subscriptions, bulk: true do |t|
      t.change :zuora_subscription_id, :string, limit: 32, null: true
      t.change :zuora_subscription_number, :string, limit: 32, null: true
    end
  end

  def self.down
    change_table :billing_sales_serve_plan_subscriptions, bulk: true do |t|
      t.change :zuora_subscription_id, :string, limit: 32, null: false
      t.change :zuora_subscription_number, :string, limit: 32, null: false
    end
  end
end
