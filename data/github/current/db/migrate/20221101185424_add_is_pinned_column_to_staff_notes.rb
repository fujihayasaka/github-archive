# typed: true

class AddIsPinnedColumnToStaffNotes < ActiveRecord::Migration[7.1]
  def up
    change_table :staff_notes, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, auto_increment: true
      t.change :user_id, :bigint, unsigned: true
      t.change :notable_id, :bigint, unsigned: true
    end

    add_column :staff_notes, :is_pinned, :boolean, null: false, default: false
  end

  def down
    change_table :staff_notes, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :user_id, :int
      t.change :notable_id, :int
    end

    remove_column :staff_notes, :is_pinned
  end
end
