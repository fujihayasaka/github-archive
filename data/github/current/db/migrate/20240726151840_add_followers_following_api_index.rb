class AddFollowersFollowingApiIndex < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :followers, bulk: true do |t|
      t.index [:following_id, :user_hidden, :user_id]
    end
  end

  def down
    change_table :followers, bulk: true do |t|
      t.remove_index [:following_id, :user_hidden, :user_id]
    end
  end
end
