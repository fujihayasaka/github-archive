# typed: true

class UsersDisplayLoginNonNull < ActiveRecord::Migration[7.1]
  def change
    change_column :users, :display_login, "varchar(40)", null: false
  end
end
