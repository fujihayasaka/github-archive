# typed: true
# frozen_string_literal: true

class AddEducationBundleToSalesServePlanSubscription < ActiveRecord::Migration[7.1]
  self.use_connection_class ApplicationRecord::Billing

  def change
    add_column :billing_sales_serve_plan_subscriptions, :education_bundle, :tinyint, null: false, default: 0
  end
end
