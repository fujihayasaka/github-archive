# typed: true
class RemoveAbilityIdFromCopilotEngagedOssUsers < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    remove_column :copilot_engaged_oss_users, :ability_id, :bigint, null: false, default: 0
  end
end
