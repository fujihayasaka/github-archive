# typed: true

class AddInUseToUserSessions < ActiveRecord::Migration[7.1]
  def up
    change_table :user_sessions, bulk: true do |t|
      t.column :in_use, :boolean, default: nil, null: true
      t.change :id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
      t.change :impersonator_id, :bigint, unsigned: true
      t.change :impersonator_session_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :user_sessions, bulk: true do |t|
      t.remove :in_use
      t.change :id, :int
      t.change :user_id, :int
      t.change :impersonator_id, :int
      t.change :impersonator_session_id, :int
    end
  end
end
