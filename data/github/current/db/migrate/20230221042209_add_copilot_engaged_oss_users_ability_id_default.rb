# typed: true
class AddCopilotEngagedOssUsersAbilityIdDefault < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_column_default :copilot_engaged_oss_users, :ability_id, from: nil, to: 0
  end
end
