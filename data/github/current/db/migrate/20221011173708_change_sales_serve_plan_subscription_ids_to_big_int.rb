# typed: false

class ChangeSalesServePlanSubscriptionIdsToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class ApplicationRecord::Billing

  def self.up
    change_table :billing_sales_serve_plan_subscriptions, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, auto_increment: true
      t.change :customer_id, :bigint, unsigned: true
    end
  end

  def self.down
    change_table :billing_sales_serve_plan_subscriptions, bulk: true do |t|
      t.change :id, :integer, auto_increment: true
      t.change :customer_id, :integer
    end
  end
end
