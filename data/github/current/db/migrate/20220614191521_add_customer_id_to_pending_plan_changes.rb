# typed: true
# frozen_string_literal: true

class AddCustomerIdToPendingPlanChanges < ActiveRecord::Migration[7.1]
  def up
    change_table :pending_plan_changes, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id, :bigint, unsigned: true, null: true
      t.change :actor_id, :bigint, unsigned: true, null: true
      t.column :customer_id, :bigint, unsigned: true, null: true, after: :user_id
      t.index [:customer_id, :is_complete]
    end
  end

  def down
    change_table :pending_plan_changes, bulk: true do |t|
      t.remove_index [:customer_id, :is_complete]
      t.remove :customer_id
      t.change :actor_id, :integer, unsigned: false, null: true
      t.change :user_id, :integer, unsigned: false, null: true
      t.change :id, :integer, unsigned: false, null: false, auto_increment: true
    end
  end
end
