# typed: true
class AddUniqueIndexToUserIdInEngagedOssUser < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_index :copilot_engaged_oss_users, :user_id, name: "index_copilot_engaged_oss_users_user_id"
  end
end
