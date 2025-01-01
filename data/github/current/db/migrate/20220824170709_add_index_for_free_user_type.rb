# typed: true
class AddIndexForFreeUserType < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_index :copilot_complimentary_users, :free_user_type, unique: false, name: "index_free_user_type"
  end
end
