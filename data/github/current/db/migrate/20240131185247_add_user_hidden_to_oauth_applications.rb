class AddUserHiddenToOauthApplications < ActiveRecord::Migration[7.2]
  def up
    change_table :oauth_applications, bulk: true do |t|
      t.boolean :user_hidden, null: false, default: false
      t.index [:user_hidden, :user_id], name: "index_user_hidden_and_user_id"
    end
  end

  def down
    change_table :oauth_applications, bulk: true do |t|
      t.remove :user_hidden
      t.remove_index [:user_hidden, :user_id], name: "index_user_hidden_and_user_id"
    end
  end
end
