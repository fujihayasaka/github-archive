class AddFollowersFollowingIndex < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :followers, bulk: true do |t|
      t.index [:following_id, :user_hidden, :created_at]

      # Update all int ID columns to bigint
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id, :bigint, unsigned: true, default: nil
      t.change :following_id, :bigint, unsigned: true, default: nil
    end
  end

  def down
    change_table :followers, bulk: true do |t|
      t.remove_index [:following_id, :user_hidden, :created_at]

      # Update all int ID columns to bigint
      t.change :id, :int, null: false, auto_increment: true
      t.change :user_id, :int, default: nil
      t.change :following_id, :int, default: nil
    end
  end
end
