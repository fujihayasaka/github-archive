# typed: true
# rubocop:disable GitHub/AvoidTypeBeforeId
class AlterIndexOnPlanSubAndSubscribable < ActiveRecord::Migration[7.1]
  def up
    change_table :subscription_items, bulk: true do |t|
      t.index [:plan_subscription_id, :subscribable_type, :subscribable_id, :organization_id], unique: true, name: "idx_sub_items_on_plan_sub_and_subscribable_and_org_id"
      t.remove_index name: "index_subscription_items_on_plan_sub_and_subscribable"
    end
  end

  def down
    change_table :subscription_items, bulk: true do |t|
      t.index [:plan_subscription_id, :subscribable_type, :subscribable_id], unique: true, name: "index_subscription_items_on_plan_sub_and_subscribable"
      t.remove_index name: "idx_sub_items_on_plan_sub_and_subscribable_and_org_id"
    end
  end
end
