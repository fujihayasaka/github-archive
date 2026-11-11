# typed: true
# frozen_string_literal: true

class SubscriptionItemsBillingCycleColumn < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :subscription_items, :billing_cycle, :integer, unsigned: true, null: true, comment: "Billing cadence for this subscription item. Independent of account-level plan_duration."
  end
end
