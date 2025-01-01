# typed: true
class UpdateIndicesForUserLogin < ActiveRecord::Migration[7.1]
  def up
    change_table :users, bulk: true do |t|
      # remove unique index on [login, business_id] in favor of unique index on login alone
      t.remove_index name: "index_users_on_login_business_id"
    end
  end

  def down
    change_table :users, bulk: true do |t|
      t.index [:login, :business_id], unique: true, name: "index_users_on_login_business_id"
    end

  end
end
