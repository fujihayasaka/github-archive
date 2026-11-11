# typed: true
# frozen_string_literal: true

class ChangeUserDashboardPinsPinnedItemIdToBigint < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table(:user_dashboard_pins, bulk: true) do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id, :bigint, unsigned: true, null: false
      t.change :pinned_item_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table(:user_dashboard_pins, bulk: true) do |t|
      t.change :id, :int, unsigned: false, null: false, auto_increment: true
      t.change :user_id, :int, unsigned: false, null: false
      t.change :pinned_item_id, :int, unsigned: false, null: false
    end
  end
end
