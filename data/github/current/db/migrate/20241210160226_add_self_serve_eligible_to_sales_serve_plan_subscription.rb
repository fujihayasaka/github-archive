# typed: true

class AddSelfServeEligibleToSalesServePlanSubscription < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::Billing

  def change
    add_column :billing_sales_serve_plan_subscriptions, :self_serve_eligible, :boolean, null: true, default: nil
  end
end
