# typed: true

class AddOrganizationIdToPendingSubscriptionItemChange < ActiveRecord::Migration[7.1]
  def change
    add_column :pending_subscription_item_changes, :organization_id, :bigint, unsigned: true, null: true
  end
end
