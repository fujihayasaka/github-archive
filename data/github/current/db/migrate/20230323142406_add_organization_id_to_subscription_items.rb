# typed: true

# rubocop:disable GitHub/AvoidTypeBeforeId
class AddOrganizationIdToSubscriptionItems < ActiveRecord::Migration[7.1]
  def up
    change_table :subscription_items, bulk: true do |t|
      t.column :organization_id, :bigint, unsigned: true, null: true
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :plan_subscription_id, :bigint, unsigned: true, null: false
      t.change :subscribable_id, :bigint, unsigned: true, null: true

      t.index [:plan_subscription_id, :quantity, :subscribable_type, :subscribable_id, :organization_id], name: "idx_sub_items_on_plan_quantity_subscribable_and_org_id"
      t.remove_index name: "index_subscription_items_on_plan_quantity_subscribable"
    end
  end

  def down
    change_table :subscription_items, bulk: true do |t|
      t.remove :organization_id
      t.change :id, :int, null: false, auto_increment: true
      t.change :plan_subscription_id, :int, null: false
      t.change :subscribable_id, :int, null: true

      t.index [:plan_subscription_id, :quantity, :subscribable_type, :subscribable_id], name: "index_subscription_items_on_plan_quantity_subscribable"
      t.remove_index name: "idx_sub_items_on_plan_quantity_subscribable_and_org_id"
    end
  end
end
